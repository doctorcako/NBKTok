import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import * as dotenv from "dotenv";
dotenv.config();

const ICOModule = buildModule("ICOModule", (m) => {
    const tokenAddress = m.getParameter("tokenAddress", process.env.TOKEN_ADDRESS );
    const ownerWallet = m.getParameter("ownerWallet", process.env.OWNER_ADDRESS);

    const ico = m.contract("IcoNBKToken", [tokenAddress, ownerWallet]);
    return { ico };
});

export default ICOModule;

// Deploy -- npx hardhat ignition deploy ignition/modules/ERC20Module.ts

