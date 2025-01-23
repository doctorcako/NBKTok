const { ethers } = require("ethers");
import fs from "fs";

const TESTNET_RPC_URL = "https://rpc-mumbai.maticvigil.com"; // RPC de la testnet
const CONTRACT_ADDRESS_TEST = "0xYourTestnetContractAddress"; // Dirección del contrato en la testnet
const ABI_TEST = [
    "function balanceOf(address account) external view returns (uint256)",
    "function totalSupply() external view returns (uint256)",
    "function totalUsers() external view returns (uint256)", // Si tienes esta función en el contrato
    "function users(uint256 index) external view returns (address)", // Para iterar sobre usuarios
];

async function fetchData() {
    const provider = new ethers.providers.JsonRpcProvider(TESTNET_RPC_URL);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI_TEST, provider);

    console.log("Conectado a la testnet");

    // Opcional: si tienes un método `totalUsers` en el contrato
    const totalUsers = await contract.totalUsers();
    console.log(`Usuarios totales: ${totalUsers.toString()}`);

    // Extraer balances
    const balances = [];
    for (let i = 0; i < totalUsers; i++) {
        const user = await contract.users(i);
        const balance = await contract.balanceOf(user);
        balances.push({ user, balance: balance.toString() });
    }

    // Guardar los datos en un archivo JSON
    fs.writeFileSync("balances-testnet.json", JSON.stringify(balances, null, 2));
    console.log("Datos extraídos y guardados en balances-testnet.json");
}

fetchData().catch(console.error);

const MAINNET_RPC_URL = "https://polygon-rpc.com"; // RPC de la mainnet
const PRIVATE_KEY = "0xYourPrivateKey"; // Llave privada de la cuenta que despliega
const CONTRACT_ADDRESS = "0xYourMainnetContractAddress"; // Dirección del contrato en la mainnet
const ABI = [
    "function setBalances(address[] memory users, uint256[] memory amounts) external",
];

async function loadData() {
    const provider = new ethers.providers.JsonRpcProvider(MAINNET_RPC_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, wallet);

    console.log("Conectado a la mainnet");

    // Leer datos del archivo JSON
    const balances = JSON.parse(JSON.stringify(fs.readFileSync("./balances-testnet.json")));

    // Preparar arrays para la llamada
    const users = balances.map((b:any) => b.user);
    const amounts = balances.map((b:any) => ethers.BigNumber.from(b.balance));

    // Dividir los datos en lotes para evitar problemas de gas
    const BATCH_SIZE = 50; // Ajusta según el tamaño de la transacción
    for (let i = 0; i < users.length; i += BATCH_SIZE) {
        const batchUsers = users.slice(i, i + BATCH_SIZE);
        const batchAmounts = amounts.slice(i, i + BATCH_SIZE);

        console.log(`Enviando lote de ${batchUsers.length} usuarios`);

        const tx = await contract.setBalances(batchUsers, batchAmounts);
        console.log("Transacción enviada:", tx.hash);
        await tx.wait();
        console.log("Lote procesado.");
    }

    console.log("Estado cargado en la mainnet");
}

loadData().catch(console.error);

