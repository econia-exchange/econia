import { useQuery, useQueryClient } from "@tanstack/react-query";
import { type MaybeHexString } from "aptos";
import type { GetStaticPaths, GetStaticProps } from "next";
import dynamic from "next/dynamic";
import Script from "next/script";
import { type PropsWithChildren, useEffect, useRef, useState } from "react";
import { toast } from "react-toastify";

import { DepthChart } from "@/components/DepthChart";
import { OrderbookTable } from "@/components/OrderbookTable";
import { Page } from "@/components/Page";
import { StatsBar } from "@/components/StatsBar";
import { OrderEntry } from "@/components/trade/OrderEntry";
import { OrdersTable } from "@/components/trade/OrdersTable";
import { TradeHistoryTable } from "@/components/trade/TradeHistoryTable";
import { useAptos } from "@/contexts/AptosContext";
import { OrderEntryContextProvider } from "@/contexts/OrderEntryContext";
import { API_URL, WS_URL } from "@/env";
import { MOCK_MARKETS } from "@/mockdata/markets";
import type { ApiMarket, ApiOrder, ApiPriceLevel } from "@/types/api";
import { type Orderbook } from "@/types/global";

import {
  type ResolutionString,
  type ThemeName,
} from "../../../public/static/charting_library";

const ORDERBOOK_DEPTH = 60;

const TVChartContainer = dynamic(
  () =>
    import("@/components/trade/TVChartContainer").then(
      (mod) => mod.TVChartContainer
    ),
  { ssr: false }
);

type Props = {
  marketData: ApiMarket | undefined;
  allMarketData: ApiMarket[];
};

type PathParams = {
  market_name: string;
};

const ChartCard: React.FC<PropsWithChildren<{ className?: string }>> = ({
  className,
  children,
}) => (
  <div
    className={"border border-neutral-600" + (className ? ` ${className}` : "")}
  >
    {children}
  </div>
);

const ChartName: React.FC<PropsWithChildren<{ className?: string }>> = ({
  className,
  children,
}) => (
  <p
    className={
      "ml-4 mt-2 font-jost font-bold text-white" +
      (className ? ` ${className}` : "")
    }
  >
    {children}
  </p>
);

export default function Market({ allMarketData, marketData }: Props) {
  const { account } = useAptos();
  const queryClient = useQueryClient();
  const ws = useRef<WebSocket | undefined>(undefined);
  const prevAddress = useRef<MaybeHexString | undefined>(undefined);
  const [isScriptReady, setIsScriptReady] = useState(false);

  // Set up WebSocket API connection
  useEffect(() => {
    ws.current = new WebSocket(WS_URL);
    ws.current.onopen = () => {
      if (marketData?.market_id == null || ws.current == null) {
        return;
      }

      // Subscribe to orderbook price level updates
      ws.current.send(
        JSON.stringify({
          method: "subscribe",
          channel: "price_levels",
          params: {
            market_id: marketData.market_id,
          },
        })
      );
    };

    // Close WebSocket connection on page close
    return () => {
      if (ws.current != null) {
        ws.current.close();
      }
    };
  }, [marketData?.market_id]);

  // Handle wallet connect and disconnect
  useEffect(() => {
    if (marketData?.market_id == null || ws.current == null) {
      return;
    }
    if (account?.address != null) {
      // If the WebSocket connection is not ready,
      // wait for the WebSocket connection to be opened.
      if (ws.current.readyState === WebSocket.CONNECTING) {
        const interval = setInterval(() => {
          if (ws.current?.readyState === WebSocket.OPEN) {
            clearInterval(interval);
          }
        }, 500);
      }

      // Subscribe to orders by account channel
      ws.current.send(
        JSON.stringify({
          method: "subscribe",
          channel: "orders",
          params: {
            market_id: marketData.market_id,
            user_address: account.address,
          },
        })
      );

      // Subscribe to fills by account channel
      ws.current.send(
        JSON.stringify({
          method: "subscribe",
          channel: "fills",
          params: {
            market_id: marketData.market_id,
            user_address: account.address,
          },
        })
      );

      // Store address for unsubscribing when wallet is disconnected.
      prevAddress.current = account.address;
    } else {
      if (prevAddress.current != null) {
        // Unsubscribe to orders by account channel
        ws.current.send(
          JSON.stringify({
            method: "unsubscribe",
            channel: "orders",
            params: {
              market_id: marketData.market_id,
              user_address: prevAddress.current,
            },
          })
        );

        // Unsubscribe to fills by account channel
        ws.current.send(
          JSON.stringify({
            method: "unsubscribe",
            channel: "fills",
            params: {
              market_id: marketData.market_id,
              user_address: prevAddress.current,
            },
          })
        );

        // Clear saved address
        prevAddress.current = undefined;
      }
    }
  }, [marketData?.market_id, account?.address]);

  // Handle incoming WebSocket messages
  useEffect(() => {
    if (marketData?.market_id == null || ws.current == null) {
      return;
    }

    ws.current.onmessage = (message) => {
      const msg = JSON.parse(message.data);

      if (msg.event === "update") {
        if (msg.channel === "orders") {
          const { order_state, market_order_id }: ApiOrder = msg.data;
          switch (order_state) {
            // TODO further discuss what toast text should be
            case "open":
              toast.success(
                `Order with order ID ${market_order_id} placed successfully.`
              );
              break;
            case "filled":
              toast.success(`Order with order ID ${market_order_id} filled.`);
              break;
            case "cancelled":
              toast.warn(`Order with order ID ${market_order_id} cancelled.`);
              break;
            case "evicted":
              toast.warn(`Order with order ID ${market_order_id} evicted.`);
              break;
          }
        } else if (msg.channel === "price_levels") {
          const priceLevel: ApiPriceLevel = msg.data;
          queryClient.setQueriesData(
            ["orderbook", marketData.market_id],
            (prevData: Orderbook | undefined) => {
              if (prevData == null) {
                return undefined;
              }
              if (priceLevel.side === "buy") {
                for (const [i, lvl] of prevData.bids.entries()) {
                  if (priceLevel.price === lvl.price) {
                    return {
                      bids: [
                        ...prevData.bids.slice(0, i),
                        { price: priceLevel.price, size: priceLevel.size },
                        ...prevData.bids.slice(i + 1),
                      ],
                      asks: prevData.asks,
                    };
                  } else if (priceLevel.price > lvl.price) {
                    return {
                      bids: [
                        ...prevData.bids.slice(0, i),
                        { price: priceLevel.price, size: priceLevel.size },
                        ...prevData.bids.slice(i),
                      ],
                      asks: prevData.asks,
                    };
                  }
                }
                return {
                  bids: [
                    ...prevData.bids,
                    { price: priceLevel.price, size: priceLevel.size },
                  ],
                  asks: prevData.asks,
                };
              } else {
                for (const [i, lvl] of prevData.asks.entries()) {
                  if (priceLevel.price === lvl.price) {
                    return {
                      bids: prevData.bids,
                      asks: [
                        ...prevData.asks.slice(0, i),
                        { price: priceLevel.price, size: priceLevel.size },
                        ...prevData.asks.slice(i + 1),
                      ],
                    };
                  } else if (priceLevel.price < lvl.price) {
                    return {
                      bids: prevData.bids,
                      asks: [
                        ...prevData.asks.slice(0, i),
                        { price: priceLevel.price, size: priceLevel.size },
                        ...prevData.asks.slice(i),
                      ],
                    };
                  }
                }
                return {
                  bids: prevData.bids,
                  asks: [
                    ...prevData.asks,
                    { price: priceLevel.price, size: priceLevel.size },
                  ],
                };
              }
            }
          );
        } else {
          // TODO
        }
      } else {
        // TODO
      }
    };
  }, [marketData, account?.address, queryClient]);

  // TODO update to include precision when backend is updated (ECO-199)
  const {
    data: orderbookData,
    isFetching: orderbookIsFetching,
    isLoading: orderbookIsLoading,
  } = useQuery(
    ["orderbook", marketData?.market_id],
    async () => {
      const res = await fetch(
        `${API_URL}/markets/${marketData?.market_id}/orderbook?depth=${ORDERBOOK_DEPTH}`
      );
      const data: Orderbook = await res.json();
      return data;
    },
    { keepPreviousData: true, refetchOnWindowFocus: false }
  );

  if (!marketData) return <Page>Market not found.</Page>;

  const defaultTVChartProps = {
    symbol: marketData.name,
    interval: "1" as ResolutionString,
    datafeedUrl: "https://dev.api.econia.exchange",
    libraryPath: "/static/charting_library/",
    clientId: "econia.exchange",
    userId: "public_user_id",
    fullscreen: false,
    autosize: true,
    studiesOverrides: {},
    theme: "Dark" as ThemeName,
    selectedMarket: marketData,
    allMarketData,
  };

  return (
    <OrderEntryContextProvider>
      <Page>
        <StatsBar selectedMarket={marketData} />
        <main className="flex w-full space-x-3 px-3 py-3">
          <div className="flex flex-1 flex-col space-y-3">
            <ChartCard className="flex min-h-[590px] flex-1 flex-col">
              {isScriptReady && <TVChartContainer {...defaultTVChartProps} />}
              <DepthChart marketData={marketData} />
            </ChartCard>
            <ChartCard>
              <ChartName className="mb-4">Orders</ChartName>
              <OrdersTable allMarketData={allMarketData} />
            </ChartCard>
          </div>
          <div className="flex min-w-[268px] flex-initial flex-col border-neutral-600">
            <ChartCard className="flex flex-1 flex-col">
              <OrderbookTable
                marketData={marketData}
                data={orderbookData}
                isFetching={orderbookIsFetching}
                isLoading={orderbookIsLoading}
              />
            </ChartCard>
          </div>
          <div className="flex min-w-[268px] flex-initial flex-col gap-4 border-neutral-600">
            <div className="flex flex-1 flex-col space-y-3">
              <ChartCard>
                <OrderEntry marketData={marketData} />
              </ChartCard>
              <ChartCard className="flex-1">
                <ChartName className="mb-3 mt-3 font-bold">
                  Trade History
                </ChartName>
                <TradeHistoryTable marketData={marketData} />
              </ChartCard>
            </div>
          </div>
        </main>
        <Script
          src="/static/datafeeds/udf/dist/bundle.js"
          strategy="lazyOnload"
          onReady={() => {
            setIsScriptReady(true);
          }}
        />
      </Page>
    </OrderEntryContextProvider>
  );
}

export const getStaticPaths: GetStaticPaths<PathParams> = async () => {
  const res = await fetch(new URL("markets", API_URL).href);
  // const allMarketData: ApiMarket[] = await res.json();
  // TODO: Working API
  const allMarketData = MOCK_MARKETS;
  const paths = allMarketData.map((market) => ({
    params: { market_name: market.name },
  }));
  return { paths, fallback: false };
};

export const getStaticProps: GetStaticProps<Props, PathParams> = async ({
  params,
}) => {
  if (!params) throw new Error("No params");
  // const allMarketData: ApiMarket[] = await fetch(
  //   new URL("markets", API_URL).href
  // ).then((res) => res.json());
  // TODO: Working API
  const allMarketData = MOCK_MARKETS;
  const marketData = allMarketData.find(
    (market) => market.name === params.market_name
  );

  return {
    props: {
      marketData,
      allMarketData,
    },
    revalidate: 600, // 10 minutes
  };
};
