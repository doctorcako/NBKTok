import { execSync } from 'child_process';
import path from 'path';
import fs from 'fs';

async function runTests() {
    const logDir = path.join(__dirname, '../test/logs');
    if (!fs.existsSync(logDir)) {
        fs.mkdirSync(logDir, { recursive: true });
    }

    try {
        console.log('Running tests...\n');
        execSync('npx hardhat test --before test/setup.ts', { 
            stdio: 'inherit',
            env: {
                ...process.env,
                FORCE_COLOR: 'true'
            }
        });
    } catch (error) {
        console.error('\nSome tests failed. Check the logs for details.');
    } finally {
        // Read and display the summary
        const summaryPath = path.join(__dirname, '../test/logs/test-summary.md');
        const errorLogPath = path.join(__dirname, '../test/logs/test-errors.log');
        
        if (fs.existsSync(summaryPath)) {
            console.log('\n=== Test Execution Summary ===\n');
            console.log(fs.readFileSync(summaryPath, 'utf8'));
        }
        
        if (fs.existsSync(errorLogPath) && fs.statSync(errorLogPath).size > 0) {
            console.log('\n=== Detailed Error Log ===\n');
            console.log(fs.readFileSync(errorLogPath, 'utf8'));
        }
    }
}

runTests().catch(console.error); 