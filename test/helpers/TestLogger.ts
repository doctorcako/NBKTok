import fs from 'fs';
import path from 'path';
import colors from 'colors';

colors.enable();

export class TestLogger {
    private static errors: Array<{
        testName: string;
        suite: string;
        error: any;
        timestamp: string;
        contractName: string;
        stackTrace?: string;
    }> = [];

    private static testResults: Map<string, Array<{
        suite: string;
        testName: string;
        status: 'passed' | 'failed';
        duration: number;
        error?: any;
    }>> = new Map();

    private static timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    private static logsDir = path.join(__dirname, '../logs');
    private static currentRunDir = path.join(this.logsDir, this.timestamp);
    private static logFile = path.join(this.currentRunDir, 'test-errors.log');
    private static summaryFile = path.join(this.currentRunDir, 'test-summary.md');
    private static historyFile = path.join(this.logsDir, 'test-history.md');

    static logError(contractName: string, testName: string, suite: string, error: any) {
        const errorKey = `${contractName}-${suite}-${testName}-${error.message}`;
        
        // Solo registrar el error si no existe ya
        if (!this.errors.some(e => 
            e.contractName === contractName && 
            e.suite === suite && 
            e.testName === testName && 
            e.error === (error.message || error)
        )) {
            const errorEntry = {
                contractName,
                testName,
                suite,
                error: error.message || error,
                timestamp: new Date().toISOString(),
                stackTrace: error.stack
            };
            
            this.errors.push(errorEntry);
            this.writeToFile(errorEntry);
        }
    }

    static logTestResult(contractName: string, suite: string, testName: string, status: 'passed' | 'failed', duration: number, error?: any) {
        if (!this.testResults.has(contractName)) {
            this.testResults.set(contractName, []);
        }

        // Evitar duplicados en los resultados
        const existingTest = this.testResults.get(contractName)?.find(t => 
            t.suite === suite && 
            t.testName === testName
        );

        if (!existingTest) {
            this.testResults.get(contractName)?.push({
                suite,
                testName,
                status,
                duration,
                error
            });

            if (status === 'failed' && error) {
                this.logError(contractName, testName, suite, error);
            }
        }
    }

    private static writeToFile(errorEntry: any) {
        if (!fs.existsSync(this.currentRunDir)) {
            fs.mkdirSync(this.currentRunDir, { recursive: true });
        }

        const logEntry = `
[${errorEntry.timestamp}]
Contract: ${errorEntry.contractName}
Suite: ${errorEntry.suite}
Test: ${errorEntry.testName}
Error: ${errorEntry.error}
${errorEntry.stackTrace ? `Stack Trace:\n${errorEntry.stackTrace}` : ''}
----------------------------------------
`;

        fs.appendFileSync(this.logFile, logEntry);
    }

    private static updateHistory(summary: string) {
        if (!fs.existsSync(this.historyFile)) {
            fs.writeFileSync(this.historyFile, '# Test Execution History\n\n');
        }

        const date = new Date();
        const formattedDate = date.toLocaleString('es-ES', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        });

        // Leer el historial actual
        const currentHistory = fs.readFileSync(this.historyFile, 'utf8');
        const runs = currentHistory.split('================================================================');
        
        // Si la última ejecución es del mismo timestamp, actualizarla en lugar de crear una nueva
        const lastRun = runs[runs.length - 1];
        if (lastRun && lastRun.includes(this.timestamp)) {
            // Actualizar la última ejecución
            runs[runs.length - 1] = `
================================================================
## Test Run - ${formattedDate}
ID: ${this.timestamp}

${summary}

[📝 Detailed Summary](${this.timestamp}/test-summary.md) | [❌ Error Log](${this.timestamp}/test-errors.log)
================================================================
`;
            fs.writeFileSync(this.historyFile, runs.join('================================================================'));
        } else {
            // Agregar nueva ejecución
            const historyEntry = `
================================================================
## Test Run - ${formattedDate}
ID: ${this.timestamp}

${summary}

[📝 Detailed Summary](${this.timestamp}/test-summary.md) | [❌ Error Log](${this.timestamp}/test-errors.log)
================================================================
`;
            fs.appendFileSync(this.historyFile, historyEntry);
        }
    }

    static writeSummary(results: any) {
        const duration = results.duration ? Number(results.duration) : 0;
        
        // Convert Map to array and reduce
        const stats = Array.from(this.testResults.values()).flat().reduce((acc: any, curr: any) => {
            acc.total++;
            if (curr.status === 'passed') acc.passed++;
            acc.duration += typeof curr.duration === 'bigint' ? 
                Number(curr.duration.toString()) : 
                Number(curr.duration || 0);
            return acc;
        }, { total: 0, passed: 0, duration: 0 });

        if (!fs.existsSync(this.currentRunDir)) {
            fs.mkdirSync(this.currentRunDir, { recursive: true });
        }

        let totalTests = 0;
        let totalPassed = 0;
        let totalFailed = 0;
        let totalDuration = 0;

        this.testResults.forEach(contractTests => {
            totalTests += contractTests.length;
            totalPassed += contractTests.filter(t => t.status === 'passed').length;
            totalFailed += contractTests.filter(t => t.status === 'failed').length;
            totalDuration += contractTests.reduce((acc, test) => acc + test.duration, 0);
        });

        const shortSummary = `
### 📊 Overview
- ✨ Total Tests: ${totalTests}
- ✅ Passed: ${totalPassed}
- ❌ Failed: ${totalFailed}
- ⏱️ Total Duration: ${totalDuration}ms

### 📋 Summary by Contract
${Array.from(this.testResults.entries()).map(([contract, tests]) => {
    const passed = tests.filter(t => t.status === 'passed').length;
    const failed = tests.filter(t => t.status === 'failed').length;
    const duration = tests.reduce((acc, test) => acc + test.duration, 0);
    return `- ${contract}: ✅ ${passed} passed, ❌ ${failed} failed (⏱️ ${duration}ms)`;
}).join('\n')}

### 🔍 Test Details
${Array.from(this.testResults.entries()).map(([contract, tests]) => {
    return `
#### ${contract}
${tests.map(test => `- ${test.status === 'passed' ? '✓' : '✗'} ${test.suite} - ${test.testName} (${test.duration}ms)`).join('\n')}`;
}).join('\n')}
`;
        this.updateHistory(shortSummary);

        // Mostrar en consola con colores
        console.log('\n=== Test Run Summary ==='.cyan);
        console.log(shortSummary);
        
        if (totalFailed > 0) {
            console.log('\n=== Failed Tests ==='.red);
            this.testResults.forEach((tests, contractName) => {
                const failedTests = tests.filter(t => t.status === 'failed');
                if (failedTests.length > 0) {
                    console.log(`\n${contractName}:`.yellow);
                    failedTests.forEach(test => {
                        console.log(`  ❌ ${test.suite} - ${test.testName}`.red);
                        if (test.error) {
                            console.log(`    Error: ${test.error.message || test.error}`.gray);
                        }
                    });
                }
            });
        }

        // Guardar el resumen detallado
        const detailedSummary = `
# Test Execution Summary
Generated at: ${new Date().toISOString()}

## 📊 Overview
- ✨ Total Tests: ${totalTests}
- ✅ Passed: ${totalPassed}
- ❌ Failed: ${totalFailed}
- ⏱️ Total Duration: ${totalDuration}ms

## 📋 Detailed Results by Contract
${this.formatDetailedResults()}

## ❌ Error Summary
Total Errors: ${this.errors.length}

${this.errors.map((error, index) => `
### ${index + 1}. ${error.contractName} - ${error.suite}
- 📝 Test: ${error.testName}
- ⏰ Time: ${error.timestamp}
- ❌ Error: ${error.error}
${error.stackTrace ? `- 🔍 Stack Trace:\n\`\`\`\n${error.stackTrace}\n\`\`\`` : ''}
`).join('\n')}
`;

        fs.writeFileSync(this.summaryFile, detailedSummary);
    }

    private static formatDetailedResults(): string {
        let output = '';
        
        this.testResults.forEach((tests, contractName) => {
            const passed = tests.filter(t => t.status === 'passed').length;
            const failed = tests.filter(t => t.status === 'failed').length;
            
            output += `\n### ${contractName}\n`;
            output += `- Total: ${tests.length}, Passed: ${passed}, Failed: ${failed}\n\n`;
            
            // Group by suite
            const suites = new Map<string, typeof tests>();
            tests.forEach(test => {
                if (!suites.has(test.suite)) {
                    suites.set(test.suite, []);
                }
                suites.get(test.suite)?.push(test);
            });

            suites.forEach((suiteTests, suiteName) => {
                output += `#### ${suiteName}\n`;
                // Primero mostrar los tests que pasaron
                suiteTests.filter(test => test.status === 'passed').forEach(test => {
                    output += `- ✓ ${test.testName} (${test.duration}ms)\n`;
                });
                // Luego mostrar los tests que fallaron
                suiteTests.filter(test => test.status === 'failed').forEach(test => {
                    output += `- ✗ ${test.testName} (${test.duration}ms)\n`;
                    if (test.error) {
                        output += `  Error: ${test.error.message || test.error}\n`;
                    }
                });
                output += '\n';
            });
        });

        return output;
    }

    static getSummary() {
        return {
            totalErrors: this.errors.length,
            errors: this.errors,
            testResults: this.testResults
        };
    }

    static cleanOldLogs(daysToKeep = 7) {
        const now = new Date().getTime();
        const maxAge = daysToKeep * 24 * 60 * 60 * 1000; // días a milisegundos

        if (fs.existsSync(this.logsDir)) {
            fs.readdirSync(this.logsDir).forEach(file => {
                const filePath = path.join(this.logsDir, file);
                const stats = fs.statSync(filePath);
                
                // Si es un directorio y es más antiguo que maxAge
                if (stats.isDirectory() && now - stats.mtimeMs > maxAge) {
                    try {
                        fs.rmSync(filePath, { recursive: true });
                        console.log(`Cleaned old logs: ${file}`.gray);
                    } catch (error) {
                        console.error(`Error cleaning logs: ${file}`.red, error);
                    }
                }
            });
        }
    }

    static clearLogs() {
        // Limpiar logs antiguos antes de una nueva ejecución
        this.cleanOldLogs();
        
        // No eliminamos los logs anteriores, solo creamos un nuevo directorio para esta ejecución
        if (!fs.existsSync(this.logsDir)) {
            fs.mkdirSync(this.logsDir, { recursive: true });
        }
        if (!fs.existsSync(this.currentRunDir)) {
            fs.mkdirSync(this.currentRunDir, { recursive: true });
        }
        this.errors = [];
        this.testResults.clear();
    }
} 