const { TestLogger } = require('../test/helpers/TestLogger');

// Limpiar logs más antiguos que 7 días
TestLogger.cleanOldLogs(7);
console.log('Old logs cleaned successfully.'); 