const fs = require('fs');
const path = require('path');
const colors = require('colors');

colors.enable();

const historyFile = path.join(__dirname, '../test/logs/test-history.md');

if (fs.existsSync(historyFile)) {
    const history = fs.readFileSync(historyFile, 'utf8');
    console.log('\n=== Test History ==='.cyan);
    console.log(history);
} else {
    console.log('No test history found.'.yellow);
} 