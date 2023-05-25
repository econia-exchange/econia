import { useWallet } from "@manahippo/aptos-wallet-adapter";
import React, { type PropsWithChildren } from "react";

import { Button } from "./Button";
import { useConnectWallet } from "@/contexts/ConnectWalletContext";

export const ConnectedButton: React.FC<
  PropsWithChildren<{ className?: string }>
> = ({ className, children }) => {
  const { connected } = useWallet();
  const { connectWallet } = useConnectWallet();

  return (
    <>
      {!connected ? (
        <Button className={className} variant="primary" onClick={connectWallet}>
          Connect Wallet
        </Button>
      ) : (
        children
      )}
    </>
  );
};
