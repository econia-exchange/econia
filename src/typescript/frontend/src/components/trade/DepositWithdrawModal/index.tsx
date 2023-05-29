import { useQuery } from "@tanstack/react-query";
import React, { useEffect } from "react";

import { API_URL } from "@/env";
import { type ApiMarket, type ApiStats } from "@/types/api";
import { type OrderBook } from "@/types/global";

import { BaseModal } from "../../BaseModal";
import { DepositWithdrawContent } from "./DepositWithdrawContent";
import { InitialContent } from "./InitialContent";
import { SelectMarketContent } from "./SelectMarketContent";

enum Step {
  Initial,
  SelectMarket,
  DepositWithdraw,
}

export const useAllMarketPrices = (allMarketData: ApiMarket[]) => {
  return useQuery<{ market_id: number; price: number }[]>(
    ["allMarketPrices", allMarketData],
    async () => {
      const data: Promise<OrderBook>[] = [];
      allMarketData.forEach((market) => {
        data.push(
          fetch(
            new URL(`market/${market.market_id}/orderbook?depth=1`, API_URL)
              .href
          ).then((res) => {
            return res.json();
          })
        );
      });
      const orderBooks = await Promise.all(data);
      return orderBooks.map((orderBook, i) => {
        return {
          market_id: allMarketData[i].market_id,
          price: (orderBook.asks[0].price + orderBook.bids[0].price) / 2,
        };
      });
    }
  );
};

export const useAllMarketStats = () => {
  return useQuery<ApiStats[]>(["allMarketStats"], async () => {
    return fetch(new URL("stats?resolution=1d", API_URL).href).then((res) => {
      return res.json();
    });
  });
};
// TODO: remove before PR
export const useAllMarketData = () => {
  return useQuery<ApiMarket[]>(["allMarketData"], async () => {
    return fetch(new URL("markets", API_URL).href).then(async (res) => {
      const d = await res.json();
      // TODO: Remove once real data exists
      return d.map((m: ApiMarket, i: number) => {
        m.recognized = i % 2 === 0 ? true : false;
        return m;
      });
    });
    // TODO: Remove mock data
    // return [
    //   {
    //     market_id: 1,
    //     name: "tETH-tUSDC",
    //     base: {
    //       account_address:
    //         "0x7c36a610d1cde8853a692c057e7bd2479ba9d5eeaeceafa24f125c23d2abf942",
    //       module_name: "test_eth",
    //       struct_name: "TestETHCoin",
    //       symbol: "tETH",
    //       name: "TestETHCoin",
    //       decimals: 8,
    //     },
    //     base_name_generic: "",
    //     quote: {
    //       account_address:
    //         "0x7c36a610d1cde8853a692c057e7bd2479ba9d5eeaeceafa24f125c23d2abf942",
    //       module_name: "test_usdc",
    //       struct_name: "TestUSDCoin",
    //       symbol: "tUSDC",
    //       name: "TestUSDCoin",
    //       decimals: 6,
    //     },
    //     lot_size: 1,
    //     tick_size: 1,
    //     min_size: 1,
    //     underwriter_id: 0,
    //     created_at: "2023-05-18T17:22:48.971737Z",
    //   }
    // ];
  });
};

export const DepositWithdrawModal: React.FC<{
  open: boolean;
  onClose: () => void;
}> = ({ open, onClose }) => {
  const [selectedMarket, setSelectedMarket] = React.useState<ApiMarket>();
  const [step, setStep] = React.useState<Step>(Step.Initial);
  const allMarketData = useAllMarketData();
  useEffect(() => {
    if (
      allMarketData.data &&
      allMarketData.data.length > 0 &&
      selectedMarket === undefined
    ) {
      setSelectedMarket(allMarketData.data?.[0]);
    }
  }, [allMarketData.data, selectedMarket]);
  return (
    <BaseModal
      open={open}
      onClose={onClose}
      onBack={
        step === Step.SelectMarket
          ? () => setStep(Step.Initial)
          : step === Step.DepositWithdraw
          ? () => setStep(Step.Initial)
          : undefined
      }
    >
      {step === Step.Initial && (
        <InitialContent
          selectedMarket={selectedMarket}
          selectMarket={() => setStep(Step.SelectMarket)}
          depositWithdraw={() => setStep(Step.DepositWithdraw)}
        />
      )}
      {step === Step.SelectMarket && (
        <SelectMarketContent
          onSelectMarket={(market) => {
            setSelectedMarket(market);
            setStep(Step.Initial);
          }}
        />
      )}
      {step === Step.DepositWithdraw &&
        (selectedMarket !== undefined ? (
          <DepositWithdrawContent selectedMarket={selectedMarket} />
        ) : (
          <div>Unexpected error: no market selected</div>
        ))}
    </BaseModal>
  );
};
