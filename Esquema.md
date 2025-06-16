|---->Pieza 1 -- Token: owner multisig wallet
|
|---->Pieza 2 -- Token Distributor: owner multisig wallet, desde el contrato token se mintean X aqui, los demás contratos       delegan la distribución a este contrato
|----> Pieza 3 -- ICO: owner multisig wallet, maneja los vestings y las verificaciones de las compras
    |---> Pieza 3A .(mas escalabilidad, unica responsabilidad del token distributor) ---> 
            ICO: El usuario interactua con el contrato ICO. La ICO transfiere los tokens comprados al Token distributor y se encarga de almacenar en una variable la cantidad de dinero que se ha vendido en la fase para que luego  
|   |---> Pieza 3B (menos escalabilidad, varias responsabilidades del token distributor)
            ICO: La direccion del contrato ICO se guarda en el token distributor para que este pueda controlar y verificar las compras de los usuarios en la ICO.
|----> Pieza 4. Emission Fases 

Escenario 1
Pieza 1+2+3A+4 = opcion a introducir otros contratos como staking y seguir la misma logica de que el token distributor solo distribuye

Escenario 2
Pieza 1+2+3B+4 = opcion a gestionar las verificaciones de compra de la ICO desde el token distributor pero cerrado a incluir otro tipo de gestion de distribucion de tokens 
