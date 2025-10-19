import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Can initialize user reputation profile",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get("wallet_1")!;
        
        let block = chain.mineBlock([
            Tx.contractCall("reputation-system", "initialize-reputation", [], user.address),
        ]);
        
        assertEquals(block.receipts[0].result.expectOk(), true);
        
        // Check profile was created
        let profileCall = chain.callReadOnlyFn("reputation-system", "get-user-reputation", [types.principal(user.address)], user.address);
        let profile = profileCall.result.expectSome().expectTuple();
        
        assertEquals(profile['reputation-score'].expectUint(), 500); // Default 50% score
        assertEquals(profile['trust-level'].expectUint(), 2); // Silver tier
    },
});

Clarinet.test({
    name: "Can rate another user and update reputation",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const rater = accounts.get("wallet_1")!;
        const ratee = accounts.get("wallet_2")!;
        
        // Initialize both users
        let initBlock = chain.mineBlock([
            Tx.contractCall("reputation-system", "initialize-reputation", [], rater.address),
            Tx.contractCall("reputation-system", "initialize-reputation", [], ratee.address),
        ]);
        
        // Rate the user
        let rateBlock = chain.mineBlock([
            Tx.contractCall("reputation-system", "rate-user", [
                types.principal(ratee.address),
                types.uint(5), // 5-star rating
                types.buff(new ArrayBuffer(32)), // Empty comment hash
                types.none() // No associated loan
            ], rater.address),
        ]);
        
        assertEquals(rateBlock.receipts[0].result.expectOk().expectUint(), 500); // Updated score returned
        
        // Check rating was recorded
        let ratingCall = chain.callReadOnlyFn("reputation-system", "get-peer-rating", [
            types.principal(rater.address),
            types.principal(ratee.address)
        ], rater.address);
        
        let rating = ratingCall.result.expectSome().expectTuple();
        assertEquals(rating['rating'].expectUint(), 5);
    },
});

Clarinet.test({
    name: "Calculates reputation score correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get("wallet_1")!;
        const rater = accounts.get("wallet_2")!;
        
        // Initialize users
        let initBlock = chain.mineBlock([
            Tx.contractCall("reputation-system", "initialize-reputation", [], user.address),
            Tx.contractCall("reputation-system", "initialize-reputation", [], rater.address),
        ]);
        
        // Record some loan activity (simulated)
        let activityBlock = chain.mineBlock([
            Tx.contractCall("reputation-system", "record-loan-completion", [
                types.principal(user.address),
                types.principal(rater.address),
                types.uint(1000),
                types.bool(true) // on-time payment
            ], user.address),
        ]);
        
        // Add peer rating
        let rateBlock = chain.mineBlock([
            Tx.contractCall("reputation-system", "rate-user", [
                types.principal(user.address),
                types.uint(5),
                types.buff(new ArrayBuffer(32)),
                types.none()
            ], rater.address),
        ]);
        
        // Calculate reputation
        let scoreCall = chain.callReadOnlyFn("reputation-system", "calculate-reputation-score", [
            types.principal(user.address)
        ], user.address);
        
        let score = scoreCall.result.expectSome().expectUint();
        console.log(`Calculated reputation score: ${score}`);
        
        // Score should be higher than default 500 due to successful loan and good rating
        assertEquals(score > 500, true);
    },
});

Clarinet.test({
    name: "Prevents self-rating",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get("wallet_1")!;
        
        let initBlock = chain.mineBlock([
            Tx.contractCall("reputation-system", "initialize-reputation", [], user.address),
        ]);
        
        // Try to rate self
        let rateBlock = chain.mineBlock([
            Tx.contractCall("reputation-system", "rate-user", [
                types.principal(user.address), // Rating self
                types.uint(5),
                types.buff(new ArrayBuffer(32)),
                types.none()
            ], user.address),
        ]);
        
        assertEquals(rateBlock.receipts[0].result.expectErr(), types.uint(205)); // ERR-SELF-RATING
    },
});

Clarinet.test({
    name: "Calculates risk category correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get("wallet_1")!;
        
        // Initialize user
        let initBlock = chain.mineBlock([
            Tx.contractCall("reputation-system", "initialize-reputation", [], user.address),
        ]);
        
        // Check initial risk category
        let riskCall = chain.callReadOnlyFn("reputation-system", "calculate-risk-category", [
            types.principal(user.address)
        ], user.address);
        
        let riskCategory = riskCall.result.expectUint();
        console.log(`Risk category: ${riskCategory}`);
        
        // New users should be high risk
        assertEquals(riskCategory >= 3, true); // Should be High or Very High risk
    },
});

Clarinet.test({
    name: "Updates achievements based on activity",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get("wallet_1")!;
        const lender = accounts.get("wallet_2")!;
        
        // Initialize user
        let initBlock = chain.mineBlock([
            Tx.contractCall("reputation-system", "initialize-reputation", [], user.address),
            Tx.contractCall("reputation-system", "initialize-reputation", [], lender.address),
        ]);
        
        // Record multiple successful loans to trigger achievements
        let activityBlocks = [];
        for (let i = 0; i < 6; i++) {
            activityBlocks.push(
                Tx.contractCall("reputation-system", "record-loan-completion", [
                    types.principal(user.address),
                    types.principal(lender.address),
                    types.uint(1000 + i * 100),
                    types.bool(true)
                ], user.address)
            );
        }
        
        let block = chain.mineBlock(activityBlocks);
        
        // Update reputation to trigger achievement check
        let updateBlock = chain.mineBlock([
            Tx.contractCall("reputation-system", "update-reputation-score", [
                types.principal(user.address)
            ], user.address),
        ]);
        
        // Check achievements
        let achievementsCall = chain.callReadOnlyFn("reputation-system", "get-user-achievements", [
            types.principal(user.address)
        ], user.address);
        
        let achievements = achievementsCall.result.expectSome().expectTuple();
        console.log('User achievements:', achievements);
        
        // Should have reliable borrower achievement
        assertEquals(achievements['reliable-borrower'].expectBool(), true);
    },
});
