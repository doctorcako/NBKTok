# **NeuroBlock Smart Contracts**

Este proyecto utiliza [Hardhat](https://hardhat.org/) para desarrollar, probar y desplegar contratos inteligentes.

---

## **Instalación del proyecto**
1. Clonar el repositorio
```bash
git clone https://github.com/NeuroBlockFoundation/NBK.git
```
2. Instalar dependencias
```bash
npm install 
```
3. Generar un archivo `.env` a partir del archivo `.env.example`

## **Estructura del proyecto**

### **Carpetas principales**
- **`contracts/`**: Contiene los contratos inteligentes en Solidity (`.sol`).
  - Ejemplo: `NBKToken.sol`.

- **`ignition/modules`**: Archivos JavaScript o TypeScript que automatizan tareas de despliegue de contratos.
  - Ejemplo: `NBKTokenModule.ts`.

- **`scripts/`**: Archivos JavaScript o TypeScript que automatizan tareas como interactuar con ellos, o realizar migraciones.
  - Ejemplo: `deploy.js`.

- **`test/`**: Contiene las pruebas de los contratos. Aquí puedes escribir tests en JavaScript o TypeScript para asegurar el correcto funcionamiento de tus contratos.
  - Ejemplo: `01-NBKToken.test.ts`.

- **`artifacts/`** (generada automáticamente): Contiene los artefactos generados tras compilar los contratos, como los bytecodes y ABIs. No se debe editar esta carpeta manualmente.

- **`cache/`** (generada automáticamente): Almacena datos temporales que Hardhat utiliza para acelerar la ejecución. Se puede eliminar en cualquier momento para liberar los objetos cacheados.

- **`node_modules/`** (generada automáticamente): Contiene las dependencias del proyecto instaladas a través de `npm`.

---

## **Comandos básicos de Hardhat**

### **Inicializar entorno local**
- **`npx hardhat node`**  
  Inicializa una testnet local con varias billeteras simuladas.

### **Compilación**
- **`npx hardhat compile`**  
  Compila todos los contratos en el directorio `contracts/` y genera los artefactos en la carpeta `artifacts/`.

### **Pruebas**
- **`npx hardhat test`**  
  Ejecuta los tests en el directorio `test/`. Antes debe de compilarse.

- **`npx hardhat test --grep "nombre_del_test"`**  
  Ejecuta solo los tests que coincidan con el nombre especificado.

- **`npx hardhat coverage`**
  Ejecuta los test y refleja la cobertura de lineas de los test (cuantas lineas han sido probadas y ejecutadas).

### **Despliegue**
- **`npx hardhat ignition deploy ./ignition/modules/NBKTokenModule.ts --network localhost|<network-defined-on-hardhat-config>`**  
  Ejecuta un despliegue del smart contract definido en el archivo en la red indicada en el comando.

### **Validar código del Smart Contract**
- **`npx hardhat verify --network <network-defined-on-hardhat-config> CONTRACT_ADDRESS "Arg1" "Arg2"`**
  Verifica el código en Etherscan u otro Explorador de bloques haciéndolo publico y accesible.
