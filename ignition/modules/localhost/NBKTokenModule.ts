import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import * as dotenv from "dotenv";
dotenv.config();

const NBKTokenModule = buildModule("NBKTokenModule", (m) => {
    const name = m.getParameter("_name", "NBKToken");
    const symbol = m.getParameter("_symbol", "NBK");
    const ownerWallet = m.getParameter("ownerWallet",process.env.OWNER_ADDRESS_LOCALHOST);

    const nbk_token = m.contract("NBKToken", [name, symbol, ownerWallet]);

    return { nbk_token };
});

export default NBKTokenModule;
