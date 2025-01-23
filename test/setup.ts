import { TestLogger } from "./helpers/TestLogger";

export function mochaGlobalSetup() {
    console.log('\nInitializing test suite...');
    TestLogger.clearLogs();
}

export function mochaGlobalTeardown() {
    console.log('\nTest suite completed.\n');
}

// También mantenemos los hooks de mocha para casos específicos
before(() => {
    console.log('Starting test execution...');
});

after(() => {
    console.log('Finished test execution.');
}); 