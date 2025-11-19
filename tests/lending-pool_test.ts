import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Can create loan request with valid parameters",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get("deployer")!;
        const borrower = accounts.get("wallet_1")!;
        
        let block = chain.mineBlock([
            // First deposit collateral
            Tx.contractCall("lending-pool", "deposit-collateral", [types.uint(5000)], borrower.address),
            // Then request loan
            Tx.contractCall("lending-pool", "request-loan", [
                types.uint(1000),    // amount
                types.uint(500),     // 5% interest rate
                types.uint(1000),    // duration in blocks
                types.uint(2000)     // collateral amount
            ], borrower.address),
        ]);
        
        assertEquals(block.receipts.length, 2);
        assertEquals(block.receipts[0].result.expectOk(), types.uint(5000));
        assertEquals(block.receipts[1].result.expectOk(), types.uint(1));
    },
});

Clarinet.test({
    name: "Can fund and repay loan successfully",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const borrower = accounts.get("wallet_1")!;
        const lender = accounts.get("wallet_2")!;
        
        let block = chain.mineBlock([
            // Setup: deposit collateral and create loan
            Tx.contractCall("lending-pool", "deposit-collateral", [types.uint(5000)], borrower.address),
            Tx.contractCall("lending-pool", "request-loan", [
                types.uint(1000), types.uint(500), types.uint(1000), types.uint(2000)
            ], borrower.address),
            // Lender funds the loan
            Tx.contractCall("lending-pool", "fund-loan", [types.uint(1)], lender.address),
        ]);
        
        assertEquals(block.receipts[2].result.expectOk(), types.uint(1));
        
        // Make payment
        let paymentBlock = chain.mineBlock([
            Tx.contractCall("lending-pool", "make-payment", [
                types.uint(1),    // loan id
                types.uint(1050)  // payment amount (principal + interest)
            ], borrower.address),
        ]);
        
        assertEquals(paymentBlock.receipts[0].result.expectOk(), types.uint(1050));
    },
});

Clarinet.test({
    name: "Can calculate loan health correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const borrower = accounts.get("wallet_1")!;
        const lender = accounts.get("wallet_2")!;
        
        // Setup loan
        let block = chain.mineBlock([
            Tx.contractCall("lending-pool", "deposit-collateral", [types.uint(5000)], borrower.address),
            Tx.contractCall("lending-pool", "request-loan", [
                types.uint(1000), types.uint(500), types.uint(1000), types.uint(2000)
            ], borrower.address),
            Tx.contractCall("lending-pool", "fund-loan", [types.uint(1)], lender.address),
        ]);
        
        // Partial payment
        let paymentBlock = chain.mineBlock([
            Tx.contractCall("lending-pool", "make-payment", [types.uint(1), types.uint(525)], borrower.address),
        ]);
        
        // Check loan health
        let healthCall = chain.callReadOnlyFn("lending-pool", "get-loan-health", [types.uint(1)], borrower.address);
        let health = healthCall.result.expectSome().expectUint();
        assertEquals(health, 50); // 50% repaid
    },
});

Clarinet.test({
    name: "Prevents invalid loan parameters",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const borrower = accounts.get("wallet_1")!;
        
        let block = chain.mineBlock([
            Tx.contractCall("lending-pool", "deposit-collateral", [types.uint(1000)], borrower.address),
            // Try to create loan with excessive interest rate
            Tx.contractCall("lending-pool", "request-loan", [
                types.uint(1000),
                types.uint(3000), // 30% - should fail (max is 20%)
                types.uint(1000),
                types.uint(500)
            ], borrower.address),
        ]);
        
        assertEquals(block.receipts[1].result.expectErr(), types.uint(108)); // ERR-INVALID-INTEREST
    },
});

Clarinet.test({
    name: "Can liquidate overdue loans",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const borrower = accounts.get("wallet_1")!;
        const lender = accounts.get("wallet_2")!;
        
        // Setup loan with short duration
        let setupBlock = chain.mineBlock([
            Tx.contractCall("lending-pool", "deposit-collateral", [types.uint(5000)], borrower.address),
            Tx.contractCall("lending-pool", "request-loan", [
                types.uint(1000), types.uint(500), types.uint(1), types.uint(2000) // 1 block duration
            ], borrower.address),
            Tx.contractCall("lending-pool", "fund-loan", [types.uint(1)], lender.address),
        ]);
        
        // Mine blocks to make loan overdue
        chain.mineEmptyBlockUntil(chain.blockHeight + 10);
        
        // Liquidate
        let liquidateBlock = chain.mineBlock([
            Tx.contractCall("lending-pool", "liquidate-loan", [types.uint(1)], lender.address),
        ]);
        
        assertEquals(liquidateBlock.receipts[0].result.expectOk(), types.uint(2000)); // Collateral amount
    },
});
