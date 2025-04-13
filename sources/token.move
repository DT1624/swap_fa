// module swap::token {
//     use std::string::String;
//
//
//     struct Token<phantom TokenType> has store {
//         value: u64,
//     }
//
//     struct TokenStore<phantom TokenType> has key {
//         token: Token<TokenType>,
//         frozen: bool,
//         // deposit_events:
//         // withdraw_events:
//     }
//
//     struct TokenInfo<phantom TokenType> has key {
//         name: String,
//         symbol: String,
//         decimal: u8,
//     }
//
//     struct MintCapability<phantom TokenType> has copy, store {}
//
//     struct FreezeCapability<phantom TokenType> has copy, store {}
//
//     struct BurnCapability<phantom TokenType> has copy, store {}
//
//
//     /*****************/
//     /* view function */
//     /*****************/
//     public fun name<TokenType>(): String acquires TokenInfo {
//         borrow_global<TokenInfo<TokenType>>(token_address<TokenType>).name
//     }
//
//     public fun symbol<TokenType>(): String acquires TokenInfo {
//         borrow_global<TokenInfo<TokenType>>(token_address<TokenType>).symbol
//     }
//
//     public fun decimal<TokenType>(): u8 acquires TokenInfo {
//         borrow_global<TokenInfo<TokenType>>(token_address<TokenType>).decimal
//     }
//
//     /********/
//     /* */
//     public fun zero<TokenType>(): Token<TokenType> {
//         spec {
//             update supply<TokenType> = supply<TokenType> + 0;
//         };
//         Token<TokenType> {
//             value: 0
//         }
//     }
//
//     public fun value<TokenType>(token: &Token<TokenType>): u64 {
//         token.value
//     }
//
//
//     public fun initialize<TokenType>(
//
//     ) {
//
//     }
//
//     public fun withdraw<TokenType>(
//         account: &signer,
//         amount: u64
//     ): Token<TokenType> {
//         zero()
//     }
//
//     public fun deposit<TokenType>(
//         account_address: address,
//         token: Token<TokenType>
//     ) {
//
//     }
//
//     public fun extract<TokenType>(
//         token: &mut Token<TokenType>,
//         amount: u64
//     ): Token<TokenType> {
//         zero()
//     }
//
//     public fun destroy_zero<TokenType>(
//         zero_token: Token<TokenType>
//     ) {
//
//     }
// }