#!/bin/zsh

# This file contains assorted developer scripts for common workflows, with
# shorthands defined in the argument parser case section at the bottom.

# Constants >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

# URL to download homebrew.
brew_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# DocGen address name.
docgen_address="0xc0deb00c"

# Move package directory.
move_dir="src/move/econia/"

# Python directory.
python_dir="src/python/"

# Relative path to this directory from Python directory.
python_dir_inverse="../../"

# Rust directory.
rust_dir="src/rust/"

# Relative path to this directory from Rust directory.
rust_dir_inverse="../../"

# SQL directory.
sql_dir="src/rust/db/migrations/"

# Relative path to this directory from SQL directory.
sql_dir_inverse="../../../../"

# TypeScript SDK directory.
ts_sdk_dir="src/typescript/sdk"

# Relative path to this directory from TypeScript SDK directory.
ts_sdk_dir_inverse="../../../"

# Secrets directory.
secrets_dir=".secrets/"

# Manifest path.
manifest=$move_dir"Move.toml"

# Incentives Move module path.
incentives_module=$move_dir"sources/incentives.move"

# Governance script path.
governance_script=$move_dir"scripts/govern.move"

# Constants <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Functions >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

# Install via brew.
function brew_install {
    package=$1                            # Package name is first argument.
    if which "$package" &>/dev/null; then # If package installed:
        echo "$package already installed" # Print notice.
    else                                  # If package not installed:
        echo "Brew installing $package"   # Print installation notice.
        brew install $package             # Install package.
    fi
}

# Generate temporary account.
function generate_temporary_account {
    cd $python_dir # Navigate to Python package directory.
    # Generate temporary account.
    poetry run python -m econia.account generate \
        $python_dir_inverse$secrets_dir \
        --type temporary
    cd $python_dir_inverse # Go back to repository root.
}

# Print authentication key message for persistent or temporary account secret.
function print_auth_key_message {
    type=$1        # Get address.
    cd $python_dir # Navigate to Python package directory.
    # Print authentication key message.
    poetry run python -m econia.account authentication-key \
        $python_dir_inverse$secrets_dir$type
    cd $python_dir_inverse # Go back to repository root.
}

# Substiute econia named address.
function set_econia_address {
    address=$1 # Get address.
    ## If address flagged as temporary or persistent type:
    if [[ $address == temporary || $address == persistent ]]; then
        # Extract authentication key from auth key message (4th line).
        address=$(print_auth_key_message $address | sed -n '4 p')
    fi             # Address now reassigned.
    cd $python_dir # Navigate to Python package directory.
    # Set address.
    poetry run python -m econia.manifest address \
        $python_dir_inverse$manifest \
        $address
    cd $python_dir_inverse # Go back to repository root.
}

# Build Move documentation.
function build_move_docs {
    set_econia_address $docgen_address
    aptos move document --include-impl --package-dir $move_dir "$@"
    set_econia_address persistent
}

# Run Move unit tests.
function test_move {
    set_econia_address 0x0 # Set Econia address to null.
    # Run Move tests with enough instruction time and optional arguments.
    aptos move test --instructions 1000000 --package-dir $move_dir "$@"
    set_econia_address persistent
}

# Run Python tests.
function test_python {
    echo "Running Python tests" # Print notice.
    cd $python_dir              # Navigate to Python package directory.
    # Doctest all source.
    find . -name "*.py" | xargs poetry run python -m doctest
    cd $python_dir_inverse # Go back to repository root.
}

# Publish Move package using REST url in ~/.aptos/config.yaml config file.
function publish {
    type=$1 # Get account type, persistent or temporary.
    # If a temporary account type, generate a temporary account.
    if [[ $type == temporary ]]; then generate_temporary_account; fi
    # Extract secret file path from auth key message (2nd line).
    secret_file_path=$(print_auth_key_message $type | sed -n '2 p')
    # Extract authentication key from auth key message (4th line).
    auth_key=$(print_auth_key_message $type | sed -n '4 p')
    set_econia_address 0x$auth_key # Set Econia address in manifest.
    # Fund the account.
    aptos account fund-with-faucet \
        --account 0x$auth_key \
        --amount 1000000000
    # Publish the package.
    aptos move publish \
        --private-key-file $secret_file_path \
        --override-size-check \
        --included-artifacts none \
        --package-dir $move_dir \
        --assume-yes
    # Print explorer link for account.
    echo https://aptos-explorer.netlify.app/account/0x$auth_key
    set_econia_address $docgen_address # Set DocGen address in manifest.
}

# Format Python code.
function format_code_python {
    echo "Formatting Python code" # Print notice.
    cd $python_dir                # Navigate to Python package directory.
    # Find all files ending in .py, pass to autoflake command (remove
    # unused imports and variables).
    find . -name "*.py" | xargs \
        poetry run autoflake \
        --in-place \
        --recursive \
        --remove-all-unused-imports \
        --remove-unused-variables \
        --ignore-init-module-imports
    poetry run isort .                  # Sort imports.
    poetry run black . --line-length 80 # Format code.
    cd $python_dir_inverse              # Go back to repository root.

}

# Format Rust code.
function format_code_rust {
    echo "Formatting Rust code"
    cd $rust_dir         # Navigate to Rust directory
    cargo fmt --all      # Format rust code
    cd $rust_dir_inverse # Return to repository root
}

# Format shell scripts.
function format_code_shell {
    echo "Formatting shell scripts" # Print notice.
    # Recursively format scripts.
    shfmt --list --write --simplify --case-indent --indent 4 .
}

# Format SQL code.
function format_code_sql {
    echo "Formatting SQL code"
    cd $sql_dir                                            # Navigate to directory with diesel migrations.
    poetry run sqlfluff fix **/*.sql --dialect postgres -f # Format code with sqlfluff.
    cd $sql_dir_inverse                                    # Return to repository root.
}

# Format TypeScript code.
function format_code_typescript {
    echo "Formatting TypeScript code"
    cd $ts_sdk_dir         # Navigate to TypeScript SDK directory.
    pnpm format            # Format code with prettier.
    pnpm lint              # Lint code with eslint.
    cd $ts_sdk_dir_inverse # Return to repository root.
}

# Format all code.
function format_code {
    format_code_python
    format_code_rust
    format_code_shell
    format_code_sql
    format_code_typescript
}

# Run script command on Move source change, passing arguments.
function run_on_source_change {
    find $move_dir"sources" -name "*.move" |
        entr -s $(echo source scripts.sh $@)
}

# Functions <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# Command line argument parsers >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

case "$1" in

    # Print hello message.
    hello) echo "Hello, Econia developer" ;;

    # Initialize dev environment.
    init)
        echo "Initializing developer environment"  # Print notice.
        if which brew &>/dev/null; then            # If brew installed:
            echo "brew already installed"          # Print notice as such.
        else                                       # Otherwise:
            echo "installing brew"                 # Print notice of installation.
            /bin/bash -c "$(curl -fsSL $brew_url)" # Install brew.
        fi
        brew_install aptos                                 # Install aptos CLI.
        brew_install entr                                  # Install tool to run on file change.
        brew_install node                                  # Install JavaScript package manager.
        brew_install poetry                                # Install Python environment manager.
        brew_install pnpm                                  # Install performant NPM variant.
        brew_install python                                # Install Python.
        brew_install rustup                                # Install Rust toolchain installer.
        brew_install shfmt                                 # Install shell script formatter.
        rustup install stable                              # Install stable Rust toolchain.
        cd $python_dir                                     # Navigate to Python package directory.
        echo "Installing Econia Python package"            # Print notice.
        poetry install                                     # Install Python package and dependencies.
        cd $python_dir_inverse                             # Go back to repository root.
        cd $sql_dir                                        # Go to SQL directory.
        echo "Installing SQL formatter Python package"     # Print notice.
        poetry install                                     # Install SQL formatter Python package and dependencies.
        cd $sql_dir_inverse                                # Go back to repository root.
        cd $ts_sdk_dir                                     # Go to TypeScript SDK directory.
        echo "Installing TypeScript dependencies via pnpm" # Print notice.
        pnpm install                                       # Install TypeScript dependencies.
        cd $ts_sdk_dir_inverse                             # Go back to repository root.
        ;;

    # Set econia address to underscore.
    a_) set_econia_address _ ;;

    # Set econia address to DocGen address.
    ad) set_econia_address $docgen_address ;;

    # Set econia address to persistent address.
    ap) set_econia_address persistent ;;

    # Develop Python (go to Python directory).
    dp)
        cd $python_dir
        echo "Now at $(pwd)"
        ;;

    # Format code.
    fc) format_code ;;

    # Update genesis incentive parameters.
    ig)
        echo "Updating genesis parameters" # Print notice.
        cd $python_dir
        # Run incentives CLI genesis command, passing remaining arguments.
        poetry run python -m econia.incentives update \
            $python_dir_inverse$incentives_module --genesis-parameters "${@:2}"
        cd $python_dir_inverse # Go back to repository root.
        ;;

    # Update script incentive parameters.
    is)
        echo "Updating script parameters" # Print notice.
        cd $python_dir
        # Run incentives CLI command, passing remaining arguments.
        poetry run python -m econia.incentives update \
            $python_dir_inverse$governance_script "${@:2}"
        cd $python_dir_inverse # Go back to repository root.
        ;;

    # Clean Move package directory.
    mc)
        echo "Cleaning Move package"
        aptos move clean --package-dir $move_dir --assume-yes
        ;;

    # Build Move documentation.
    md) build_move_docs ;;

    # Run pre-commit checks.
    pc)
        test_move       # Test Move code.
        build_move_docs # Build docs.
        format_code     # Format code.
        ;;

    # Publish to persistent account.
    pp) publish persistent ;;

    # Publish to temporary account.
    pt) publish temporary ;;

    # Run all Python tests.
    tp) test_python ;;

    # Run all Move unit tests, passing possible additional arguments.
    tm) test_move "${@:2}" ;;

    # Run Move unit tests with a filter, passing possible additional arguments.
    tf) test_move --filter "${@:2}" ;;

    # Watch source code, rebuilding docs when it changes.
    wd) run_on_source_change md "${@:2}" ;;

    # Watch source code, running Move tests when it changes.
    wt) run_on_source_change tm "${@:2}" ;;

    # Print invalid option.
    *) echo Invalid ;;

esac

# Command line argument parsers <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
