terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.2.0"
    }
  }
}

provider "google" {
  credentials = file(var.credentials_file)
  project     = var.project
  region      = var.region
  zone        = var.zone
}

provider "google-beta" {
  credentials = file(var.credentials_file)
  project     = var.project
  region      = var.region
}

locals {
  competition_metadata_dir = "src/rust/dbv2"
  db_conn_str_admin = replace(
    local.db_conn_str_base,
    "IP_ADDRESS",
    "${local.postgres_public_ip}"
  )
  db_conn_str_base = join("", [
    "postgres://postgres:${var.db_root_password}@",
    "IP_ADDRESS:5432/econia"
  ])
  db_conn_str_private = replace(
    local.db_conn_str_base,
    "IP_ADDRESS",
    "${local.postgres_private_ip}"
  )
  docker_artifact_base  = "${var.region}-docker.pkg.dev/${var.project}/images/IMAGE"
  econia_repo_root      = "../../.."
  migrations_dir        = "src/rust/dbv2"
  postgres_private_ip   = google_sql_database_instance.postgres.private_ip_address
  postgres_public_ip    = google_sql_database_instance.postgres.public_ip_address
  processor_config_path = "src/docker/processor/config.yaml"
  service_account_name  = "terraform@${var.project}.iam.gserviceaccount.com"
  ssh_pubkey            = "ssh/gcp.pub"
  ssh_secret            = "ssh/gcp"
  ssh_username          = "bootstrapper"
  terraform_dir         = "src/terraform/internal-dss"
}

resource "terraform_data" "config_environment" {
  provisioner "local-exec" {
    command = join(" && ", [
      # Allow service account to edit project.
      join(" ", [
        "gcloud projects add-iam-policy-binding ${var.project}",
        "--member \"serviceAccount:${local.service_account_name}\"",
        "--role \"roles/editor\""
      ]),
      # Next two are to enable private IP for PostgreSQL.
      # https://stackoverflow.com/a/54351644
      # https://stackoverflow.com/questions/54278828
      # https://serverfault.com/questions/942115
      join(" ", [
        "gcloud projects add-iam-policy-binding ${var.project}",
        "--member \"serviceAccount:${local.service_account_name}\"",
        "--role \"roles/servicenetworking.serviceAgent\""
      ]),
      join(" ", [
        "gcloud projects add-iam-policy-binding ${var.project}",
        "--member \"serviceAccount:${local.service_account_name}\"",
        "--role \"roles/compute.networkAdmin\""
      ]),
      # Enable public endpoint for Cloud Run URL.
      # https://stackoverflow.com/a/61250654
      join(" ", [
        "gcloud projects add-iam-policy-binding ${var.project}",
        "--member \"serviceAccount:${local.service_account_name}\"",
        "--role \"roles/run.admin\""
      ]),
      # Enable service APIs.
      "gcloud services enable artifactregistry.googleapis.com",
      "gcloud services enable cloudbuild.googleapis.com",
      "gcloud services enable cloudresourcemanager.googleapis.com",
      "gcloud services enable compute.googleapis.com",
      "gcloud services enable run.googleapis.com",
      "gcloud services enable runapps.googleapis.com",
      "gcloud services enable servicenetworking.googleapis.com",
      "gcloud services enable sqladmin.googleapis.com",
      "gcloud services enable vpcaccess.googleapis.com",
      # Set config defaults.
      "gcloud config set artifacts/location ${var.region}",
      "gcloud config set compute/zone ${var.zone}",
      "gcloud config set run/region ${var.region}",
    ])
  }
}

resource "google_sql_database_instance" "postgres" {
  database_version    = "POSTGRES_14"
  deletion_protection = false
  depends_on = [
    google_service_networking_connection.sql_network_connection,
    terraform_data.config_environment,
  ]
  provider      = google-beta
  root_password = var.db_root_password
  settings {
    insights_config {
      query_insights_enabled = true
      query_plans_per_minute = 20
      query_string_length    = 4500
    }
    ip_configuration {
      authorized_networks {
        value = var.db_admin_public_ip
      }
      ipv4_enabled    = true
      private_network = google_compute_network.sql_network.id
    }
    tier = "db-custom-4-16384"
  }
}

resource "google_sql_database" "database" {
  deletion_policy = "ABANDON"
  instance        = google_sql_database_instance.postgres.name
  name            = "econia"
}

resource "terraform_data" "run_migrations" {
  depends_on = [google_sql_database.database]
  provisioner "local-exec" {
    environment = {
      DATABASE_URL = local.db_conn_str_admin
    }
    command = join(" && ", [
      "diesel database reset",
      "psql ${local.db_conn_str_admin} -c 'GRANT web_anon to postgres'"
    ])
    working_dir = "${local.econia_repo_root}/${local.migrations_dir}"
  }
}

resource "google_compute_network" "sql_network" {
  name       = "sql-network"
  depends_on = [terraform_data.config_environment]
  provider   = google-beta
}

resource "google_compute_global_address" "private_ip_address" {
  address_type  = "INTERNAL"
  depends_on    = [terraform_data.config_environment]
  name          = "private-ip-address"
  network       = google_compute_network.sql_network.id
  provider      = google-beta
  prefix_length = 16
  purpose       = "VPC_PEERING"
}

resource "google_service_networking_connection" "sql_network_connection" {
  network                 = google_compute_network.sql_network.id
  provider                = google-beta
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
  service                 = "servicenetworking.googleapis.com"
  provisioner "local-exec" {
    when = destroy
    # Manually destroy VPC peering.
    # This is because the dependency solver doesn't properly destroy.
    # https://github.com/hashicorp/terraform-provider-google/issues/16275
    command = join(" ", [
      "gcloud compute networks peerings delete",
      "servicenetworking-googleapis-com",
      "--network sql-network",
      "--quiet"
    ])
  }
}

resource "google_artifact_registry_repository" "images" {
  depends_on    = [terraform_data.config_environment]
  location      = var.region
  repository_id = "images"
  format        = "DOCKER"
}

resource "terraform_data" "build_processor" {
  depends_on = [google_artifact_registry_repository.images]
  provisioner "local-exec" {
    command = join(" ", [
      "gcloud builds submit .",
      "--config ${local.terraform_dir}/cloudbuild.processor.yaml",
      "--substitutions _REGION=${var.region}"
    ])
    environment = {
      PROJECT_ID = var.project
    }
    working_dir = local.econia_repo_root
  }
}

resource "terraform_data" "build_aggregator" {
  depends_on = [google_artifact_registry_repository.images]
  provisioner "local-exec" {
    command = join(" ", [
      "gcloud builds submit .",
      "--config ${local.terraform_dir}/cloudbuild.aggregator.yaml",
      "--substitutions _REGION=${var.region}"
    ])
    environment = {
      PROJECT_ID = var.project
    }
    working_dir = local.econia_repo_root
  }
}

resource "google_compute_disk" "processor_disk" {
  depends_on = [terraform_data.config_environment]
  name       = "processor-disk"
  size       = 1
}

resource "google_compute_firewall" "bootstrapper_ssh" {
  depends_on = [terraform_data.config_environment]
  name       = "bootstrapper-ssh"
  network    = "default"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = [var.db_admin_public_ip]
}

resource "google_compute_instance" "bootstrapper" {
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  connection {
    host        = self.network_interface.0.access_config.0.nat_ip
    private_key = file(local.ssh_secret)
    type        = "ssh"
    user        = local.ssh_username
  }
  depends_on = [
    google_compute_disk.processor_disk,
    google_compute_firewall.bootstrapper_ssh,
  ]
  metadata = {
    ssh-keys = "${local.ssh_username}:${file(local.ssh_pubkey)}"
  }
  machine_type = "n2-standard-2"
  name         = "bootstrapper"
  network_interface {
    network = "default"
    access_config {}
  }
  provisioner "file" {
    source      = "${local.econia_repo_root}/${local.processor_config_path}"
    destination = "/home/${local.ssh_username}/config.yaml"
  }
  # Attach disk here rather than in declaractive config, then detach soon after.
  # This is so that upon state refreshes the instance doesn't appear misconfigured.
  provisioner "local-exec" {
    command = join(" ", [
      "gcloud compute instances attach-disk bootstrapper",
      "--disk processor-disk",
      "--device-name processor-disk"
    ])
  }
  # Format and mount disk, copy config into it, update private connection string.
  # https://cloud.google.com/compute/docs/disks/format-mount-disk-linux#format_linux
  # https://medium.com/@DazWilkin/compute-engine-identifying-your-devices-aeae6c01a4d7
  provisioner "remote-exec" {
    inline = [
      "PROCESSOR_CONFIG_MOUNT_PATH=/mnt/disks/processor/data/config.yaml",
      "PROCESSOR_DISK_DEVICE_PATH=/dev/disk/by-id/google-processor-disk",
      join(" ", [
        "sudo mkfs.ext4",
        "-m 0",
        "-E lazy_itable_init=0,lazy_journal_init=0,discard",
        "$PROCESSOR_DISK_DEVICE_PATH"
      ]),
      "sudo mkdir -p /mnt/disks/processor",
      join(" ", [
        "sudo mount -o",
        "discard,defaults",
        "$PROCESSOR_DISK_DEVICE_PATH",
        "/mnt/disks/processor"
      ]),
      "sudo chmod a+w /mnt/disks/processor",
      "mkdir /mnt/disks/processor/data",
      # Substitute private connection string into config.
      join(" ", [
        "sed -E",
        join("", [
          "'s/(postgres_connection_string: )(.+)/\\1",
          # Escape forward slashes in private connection string.
          replace(local.db_conn_str_private, "/", "\\/"),
          "/g'",
        ]),
        "/home/${local.ssh_username}/config.yaml >",
        "$PROCESSOR_CONFIG_MOUNT_PATH"
      ]),
      "echo Processor config:",
      "while read line; do ",
      "echo \"$line\"",
      "done<$PROCESSOR_CONFIG_MOUNT_PATH"
    ]
  }
  # Detach disk, stop bootstrapper after preparing the processor config file.
  provisioner "local-exec" {
    command = join(" && ", [
      "gcloud compute instances stop bootstrapper",
      "gcloud compute instances detach-disk bootstrapper --disk processor-disk",
    ])
  }
}

# No declarative resource for VM with container.
# Running with container for auto-restart.
# https://github.com/hashicorp/terraform-provider-google/issues/5832
resource "terraform_data" "deploy_processor" {
  depends_on = [
    google_compute_instance.bootstrapper,
    terraform_data.run_migrations,
    terraform_data.build_processor,
  ]
  provisioner "local-exec" {
    command = join(" && ", [
      join(" ", [
        "gcloud compute instances create-with-container processor",
        "--container-image",
        replace(local.docker_artifact_base, "IMAGE", "processor"),
        "--container-mount-disk",
        join(",", [
          "mount-path=/config",
          "name=processor-disk"
        ]),
        "--disk",
        join(",", [
          "auto-delete=no",
          "device-name=processor-disk",
          "name=processor-disk",
        ]),
        "--network ${google_compute_network.sql_network.id}"
      ])
    ])
  }
  provisioner "local-exec" {
    when = destroy
    command = join(" && ", [
      "gcloud compute instances delete processor --quiet",
    ])
  }
}

# No declarative resource for VM with container.
# Running with container for auto-restart.
# https://github.com/hashicorp/terraform-provider-google/issues/5832
resource "terraform_data" "deploy_aggregator" {
  depends_on = [
    terraform_data.build_aggregator,
    terraform_data.deploy_processor,
    terraform_data.run_migrations,
  ]
  provisioner "local-exec" {
    command = join(" && ", [
      join(" ", [
        "gcloud compute instances create-with-container aggregator",
        "--container-env",
        join(",", [
          "APTOS_NETWORK=${var.aptos_network}",
          "DATABASE_URL=${local.db_conn_str_private}"
        ]),
        "--container-image",
        replace(local.docker_artifact_base, "IMAGE", "aggregator"),
        "--network ${google_compute_network.sql_network.id}"
      ])
    ])
  }
  provisioner "local-exec" {
    when    = destroy
    command = "gcloud compute instances delete aggregator --quiet"
  }
}

resource "google_compute_subnetwork" "connector_subnetwork" {
  name          = "connector-subnetwork"
  ip_cidr_range = "10.8.0.0/28"
  region        = var.region
  network       = google_compute_network.sql_network.id
}

resource "google_vpc_access_connector" "vpc_connector" {
  depends_on = [terraform_data.run_migrations]
  name       = "vpc-connector"
  subnet {
    name = google_compute_subnetwork.connector_subnetwork.name
  }
}

data "google_iam_policy" "no_auth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_v2_service" "postgrest" {
  location = var.region
  name     = "postgrest"
  template {
    containers {
      image = "postgrest/postgrest:v11.2.1"
      env {
        name  = "PGRST_DB_ANON_ROLE"
        value = "web_anon"
      }
      env {
        name  = "PGRST_DB_MAX_ROWS"
        value = var.postgrest_max_rows
      }
      env {
        name  = "PGRST_DB_SCHEMA"
        value = "api"
      }
      env {
        name  = "PGRST_DB_URI"
        value = local.db_conn_str_private
      }
      ports {
        container_port = 3000
      }
    }
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }
    vpc_access {
      connector = google_vpc_access_connector.vpc_connector.id
      egress    = "ALL_TRAFFIC"
    }
  }
}

resource "google_cloud_run_service_iam_policy" "no_auth_postgrest" {
  location    = google_cloud_run_v2_service.postgrest.location
  project     = google_cloud_run_v2_service.postgrest.project
  service     = google_cloud_run_v2_service.postgrest.name
  policy_data = data.google_iam_policy.no_auth.policy_data
}

resource "google_cloud_run_v2_service" "websockets" {
  location = var.region
  name     = "websockets"
  template {
    containers {
      image = "diogob/postgres-websockets:0.11.2.1"
      env {
        name  = "PGWS_CHECK_LISTENER_INTERVAL"
        value = 1000
      }
      env {
        name  = "PGWS_DB_URI"
        value = local.db_conn_str_private
      }
      env {
        name  = "PGWS_JWT_SECRET"
        value = var.ws_jwt_secret
      }
      env {
        name  = "PGWS_LISTEN_CHANNEL"
        value = "econiaws"
      }
      ports {
        container_port = 3000
      }
      resources {
        limits = {
          memory = "1024Mi"
        }
      }
    }
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }
    vpc_access {
      connector = google_vpc_access_connector.vpc_connector.id
      egress    = "ALL_TRAFFIC"
    }
  }
}

resource "google_cloud_run_service_iam_policy" "no_auth_websockets" {
  location    = google_cloud_run_v2_service.websockets.location
  project     = google_cloud_run_v2_service.websockets.project
  service     = google_cloud_run_v2_service.websockets.name
  policy_data = data.google_iam_policy.no_auth.policy_data
}
