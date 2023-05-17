import { useWallet } from "@manahippo/aptos-wallet-adapter";
import { useState } from "react";

import { Button } from "@/components/Button";
import { ConnectedButton } from "@/components/ConnectedButton";
import { OrderEntryInput } from "@/components/trade/OrderEntry/OrderEntryInput";
import { useCoinBalance } from "@/hooks/useCoinBalance";
import { type ApiMarket } from "@/types/api";
import { type Side } from "@/types/global";
import { TypeTag } from "@/types/move";

import { OrderEntryInfo } from "./OrderEntryInfo";

export const MarketOrderEntry: React.FC<{
  marketData: ApiMarket;
  side: Side;
}> = ({ marketData, side }) => {
  const { account } = useWallet();
  // TODO: Replace with real market price
  const [price, setPrice] = useState<string>("12.42");
  const [amount, setAmount] = useState<string>("");
  const baseBalance = useCoinBalance(
    marketData.base ? TypeTag.fromApiCoin(marketData.base) : null,
    account?.address
  );
  const quoteBalance = useCoinBalance(
    TypeTag.fromApiCoin(marketData.quote),
    account?.address
  );

  return (
    <>
      <div className="mx-4">
        <OrderEntryInput
          value={price}
          onChange={setPrice}
          startAdornment="MARKET PRICE"
          endAdornment={marketData.quote.symbol}
          type="number"
          placeholder="0.00"
          disabled
        />
      </div>
      <hr className="my-4 border-neutral-600" />
      <div className="mx-4 flex flex-col gap-4">
        <OrderEntryInput
          value={amount}
          onChange={setAmount}
          startAdornment="AMOUNT"
          endAdornment={marketData.base?.symbol}
          type="number"
          placeholder="0.00"
        />
        <OrderEntryInput
          value={(
            parseFloat(price === "" ? "0" : price) *
            parseFloat(amount === "" ? "0" : amount)
          ).toFixed(4)}
          startAdornment="TOTAL"
          endAdornment={marketData.quote?.symbol}
          type="number"
          placeholder="0.00"
          disabled
        />
      </div>
      <hr className="my-4 border-neutral-600" />
      <div className="mx-4 mb-4 flex flex-col gap-4">
        <OrderEntryInfo label="EST. FEE" value="--" />
        <ConnectedButton className="w-full">
          <Button
            variant={side === "buy" ? "green" : "red"}
            className={`w-full`}
          >
            {side === "buy" ? "Buy" : "Sell"} {marketData.base?.symbol}
          </Button>
        </ConnectedButton>
        <OrderEntryInfo
          label={`${marketData.base?.symbol} AVAIABLE`}
          value={`${baseBalance.data ?? "--"} ${marketData.base?.symbol}`}
        />
        <OrderEntryInfo
          label={`${marketData.quote?.symbol} AVAIABLE`}
          value={`${quoteBalance.data ?? "--"} ${marketData.quote?.symbol}`}
        />
      </div>
    </>
  );
};
