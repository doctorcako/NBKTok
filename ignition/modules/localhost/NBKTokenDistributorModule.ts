import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import * as dotenv from "dotenv";
dotenv.config();

const NBKTokenDistributorModule = buildModule("NBKTokenDistributorModule", (m) => {
    const tokenAddress = m.getParameter("tokenAddress", process.env.TOKEN_ADDRESS_LOCALHOST);
    const gnosisSafeWallet = m.getParameter("gnosisSafeWallet", process.env.OWNER_ADDRESS_LOCALHOST);
    const dailyLimit = m.getParameter("dailyLimit","1000");

    const nbk_token_distributor = m.contract("TokenDistributor", [tokenAddress, gnosisSafeWallet, dailyLimit]);
    return { nbk_token_distributor };
});

export default NBKTokenDistributorModule;

// Deploy -- npx hardhat ignition deploy ignition/modules/ERC20Module.ts

