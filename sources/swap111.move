// module swap::swap {
//     use std::option;
//     use std::signer;
//     use std::string::{String, utf8};
//     use aptos_std::type_info;
//     use aptos_framework::account;
//     use aptos_framework::account::SignerCapability;
//     use aptos_framework::event;
//     use aptos_framework::resource_account;
//     use swap::swap_fa::MintCapability;
//     use swap::swap_untils;
//
//     /************/
//     /* constant */
//     /************/
//
//     /* constant parameters */
//     const ZERO_ACCOUNT: address = @zero;
//     const DEFAULT_ADMIN: address = @admin;
//     const DEV: address = @dev;
//     const RESOURCE_ACCOUNT: address = @swap;
//
//     const MAX_TOKEN_NAME_LENGTH: u64 = 32;
//
//     /* constant errors */
//     const EAREADY_INITIALIZED: u64 = 1;
//     // error if sender is not admin
//     const ENOT_ADMIN: u64 = 2;
//     const EINVALID_AMOUNT: u64 = 3;
//     const EINSUFFICIENT_AMOUNT: u64 = 4;
//     const EINSUFFICIENT_LIQUIDITY: u64 = 5;
//     const EINSUFFICIENT_OUTPUT_AMOUNT: u64 = 6;
//
//     /**********/
//     /* struct */
//     /**********/
//     struct LPToken<phantom X, phantom Y> has key {}
//
//     struct TokenPairMetadata<phantom X, phantom Y> has key {
//         creator: address,
//         fee_amount: token::Token<LPToken<X, Y>>,
//         k_last: u128,
//         balance_x: token::Token<X>,
//         balance_y: token::Token<Y>,
//         mint_cap: token::MintCapability<LPToken<X, Y>>,
//         burn_cap: token::BurnCapability<LPToken<X, Y>>,
//         freeze_cap: token::BurnCapability<LPToken<X, Y>>,
//     }
//
//     struct TokenPairReserve<phantom X, phantom Y> has key {
//         reserve_x: u64,
//         reserve_y: u64,
//         block_timestamp_last: u64
//     }
//
//     struct SwapInfo has key {
//         signer_cap: account::SignerCapability,
//         fee_to: address,
//         admin: address,
//         pair_created: event::EventHandle<PairCreatedEvent>
//     }
//
//     /****************/
//     /* struct event */
//     /****************/
//
//     //Emitted when a new trading pair is created.
//     struct PairCreatedEvent has drop, store {
//         user: address,
//         token_x: String,
//         token_y: String,
//     }
//
//     // Holds event handles for liquidity operations and swaps
//     struct PairEventHolder<phantom X, phantom Y> has key {
//         add_liquidity: event::EventHandle<AddLiquidityEvent<X, Y>>,
//         remove_liquidity: event::EventHandle<RemoveLiquidityEvent<X, Y>>,
//         swap: event::EventHandle<SwapEvent<X, Y>>,
//     }
//
//     // Emits an event after successfully adding liquidity
//     struct AddLiquidityEvent<phantom X, phantom Y> has drop, store {
//         user: address,
//         amount_x: u64,
//         amount_y: u64,
//         liquidity: u64,
//         fee_amount: u64
//     }
//
//     // emits an event after successfully removing liquidity
//     struct RemoveLiquidityEvent<phantom X, phantom Y> has drop, store {
//         user: address,
//         amount_x: u64,
//         amount_y: u64,
//         liquidity: u64,
//         fee_amount: u64
//     }
//
//     // emits an event after successfully swap token
//     struct SwapEvent<phantom X, phantom Y> has drop, store {
//         user: address,
//         amount_x_in: u64,
//         amount_y_in: u64,
//         amount_x_out: u64,
//         amount_y_out: u64
//     }
//
//
//     fun init_module(sender: &signer) {
//         let signer_cap: SignerCapability = resource_account::retrieve_resource_account_cap(sender, DEV);
//         let resource_signer: signer = account::create_signer_with_capability(&signer_cap);
//         move_to(
//             &resource_signer,
//             SwapInfo {
//                 signer_cap,
//                 fee_to: ZERO_ACCOUNT,
//                 admin: DEFAULT_ADMIN,
//                 pair_created: account::new_event_handle<PairCreatedEvent>(&resource_signer),
//             }
//         );
//     }
//
//     public(friend)fun create_pair<X: key, Y: key> (sender: &signer) acquires SwapInfo {
//         assert!(!is_pair_created<X, Y>(), EAREADY_INITIALIZED);
//
//         let sender_address: address = signer::address_of(sender);
//         let swap_info: &mut SwapInfo = borrow_global_mut<SwapInfo>(DEFAULT_ADMIN);
//         let resource_signer: signer = account::create_signer_with_capability(&swap_info.signer_cap);
//
//         let lp_name: String = utf8(b"movement-");
//         let name_x: String = token::symbol<X>();
//         let name_y: String = token::symbol<Y>();
//
//         lp_name.append(name_x);
//         lp_name.append_utf8(b"-");
//         lp_name.append(name_y);
//         lp_name.append_utf8(b"-LP");
//         if (lp_name.length() > MAX_TOKEN_NAME_LENGTH) {
//             lp_name = utf8(b"Movement LPs");
//         };
//
//         let (burn_cap, freeze_cap, min_cap) = token::initialize<LPToken<X, Y>>(
//
//         );
//
//         move_to<TokenPairReserve<X, Y>>(
//             &resource_signer,
//             TokenPairReserve<X, Y> {
//                 reserve_x: 0,
//                 reserve_y: 0,
//                 block_timestamp_last: 0
//             }
//         );
//
//         move_to<TokenPairMetadata<X, Y>>(
//             &resource_signer,
//             TokenPairMetadata<X, Y> {
//                 creator: sender_address,
//                 fee_amount: token::zero<LPToken<X, Y>>(),
//                 k_last: 0,
//                 balance_x: token::zero<X>(),
//                 balance_y: token::zero<Y>(),
//                 mint_cap,
//                 burn_cap,
//                 freeze_cap
//             }
//         );
//
//         move_to<PairEventHolder<X, Y>>(
//             &resource_signer,
//             PairEventHolder<X, Y> {
//                 add_liquidity: account::new_event_handle<AddLiquidityEvent<X, Y>>(&resource_signer),
//                 remove_liquidity: account::new_event_handle<RemoveLiquidityEvent<X, Y>>(&resource_signer),
//                 swap: account::new_event_handle<SwapEvent<X, Y>>(&resource_signer)
//             }
//         );
//
//         let token_x: String = type_info::type_name<X>();
//         let token_y: String = type_info::type_name<Y>();
//
//         event::emit_event<PairCreatedEvent>(
//             &mut swap_info.pair_created,
//             PairCreatedEvent {
//                 user: sender_address,
//                 token_x,
//                 token_y
//             }
//         );
//
//         register_lp<X, Y>(&resource_signer);
//     }
//
//     public fun register_lp<X, Y>(sender: &signer) {
//         token::register<LPToken<X, Y>>(sender);
//     }
//
//     public fun is_pair_created<X, Y>(): bool {
//         exists<TokenPairReserve<X, Y>>(RESOURCE_ACCOUNT)
//     }
//
//     public fun lp_balance<X, Y>(addr: address): u64 {
//         token::balance<LPToken<X, Y>>(addr)
//     }
//
//     public fun total_lp_supply<X, Y>(): u128 {
//         option::get_with_default(
//             &token::supply<LPToken<X, Y>>,
//             0u128
//         )
//     }
//
//     public fun token_reverse<X, Y>(): (u64, u64, u64) acquires TokenPairReserve {
//         let reverse: &TokenPairReserve<X, Y> = borrow_global<TokenPairReserve<X, Y>>(RESOURCE_ACCOUNT);
//         (
//             reverse.reserve_x,
//             reverse.reserve_y,
//             reverse.block_timestamp_last
//         )
//     }
//
//     public fun token_balance<X, Y>(): (u64, u64) acquires TokenPairMetadata {
//         let metadata: &TokenPairMetadata<X, Y> = borrow_global<TokenPairMetadata<X, Y>>(RESOURCE_ACCOUNT);
//         (
//             token::value<X>(&metadata.balance_x),
//             token::value<Y>(&metadata.balance_y)
//         )
//     }
//
//     public fun check_or_register_coin<X>(sender: &signer) {
//         let sender_address: address = signer::address_of(sender);
//         if (!token::is_account_registered<X>(sender_address)) {
//             token::register<X>(sender);
//         }
//     }
//
//     public fun admin(): address acquires SwapInfo {
//         let swap_info: &SwapInfo = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
//         swap_info.admin
//     }
//
//     public fun fee_to(): address acquires SwapInfo {
//         let swap_info: &SwapInfo = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
//         swap_info.fee_to
//     }
//
//     /********************/
//     /* Update functions */
//     /********************/
//     public(friend) fun add_liquidity<X, Y>(
//         sender: &signer,
//         amount_x: u64,
//         amount_y: u64
//     ): (u64, u64, u64) acquires TokenPairReserve, PairEventHolder {
//         let (a_x, a_y, token_lp, fee_amount, token_left_x, token_left_y): (
//         u64, u64, token::Token<LPToken<X, Y>>, u64, token::Token<X>, token::Token<Y>
//         ) = add_liquidity_direct(
//             token::withdraw(sender, amount_x),
//             token::withdraw(sender, amount_y)
//         );
//         let sender_address: address = signer::address_of(sender);
//         let lp_amount: u64 = token::value<LPToken<X, Y>>(&token_lp);
//         assert!(lp_amount > 0, EINSUFFICIENT_LIQUIDITY);
//
//         check_or_register_coin<LPToken<X, Y>>(sender);
//         token::deposit(sender_address, token_lp);
//         token::deposit(sender_address, token_left_x);
//         token::deposit(sender_address, token_left_y);
//
//         //event
//         let pair_event_holder: &mut PairEventHolder<X, Y> = borrow_global_mut<PairEventHolder<X, Y>>(RESOURCE_ACCOUNT);
//         event::emit_event<AddLiquidityEvent<X, Y>>(
//             &mut pair_event_holder.add_liquidity,
//             AddLiquidityEvent<X, Y> {
//                 user: sender_address,
//                 amount_x: a_x,
//                 amount_y: a_y,
//                 liquidity: lp_amount,
//                 fee_amount: (fee_amount as u64)
//             }
//         );
//         (a_x, a_y, lp_amount)
//     }
//
//     fun add_liquidity_direct<X, Y>(
//         x: token::Token<X>,
//         y: token::Token<Y>
//     ): (u64, u64, token::Token<LPToken<X, Y>>, u64, token::Token<X>, token::Token<Y>) acquires TokenPairReserve {
//         let amount_x: u64 = token::value<X>(&x);
//         let amount_y: u64 = token::value<Y>(&y);
//         let (reverse_x, reverse_y, _): (u64, u64, u64) = token_reverse<X, Y>();
//
//         let (a_x, a_y): (u64, u64) = if (reverse_x == 0 || reverse_y == 0) {
//             (amount_x, amount_y)
//         } else {
//             let amount_y_optiaml: u64 = swap_untils::quote_y(amount_x, reverse_x, reverse_y);
//             if (amount_y_optiaml <= amount_y) {
//                 (amount_x, amount_y_optiaml)
//             } else {
//                 let amount_x_optimal: u64 = swap_untils::quote_x(amount_y, reverse_x, reverse_y);
//                 assert!(amount_x_optimal <= amount_x, EINVALID_AMOUNT);
//                 (amount_x_optimal, amount_y)
//             }
//         };
//
//         assert!(a_x <= amount_x, EINSUFFICIENT_AMOUNT);
//         assert!(a_y <= amount_y, EINSUFFICIENT_AMOUNT);
//
//         let left_x: token::Token<X> = token::extract(&mut x, amount_x - a_x);
//         let left_y: token::Token<Y> = token::extract(&mut y, amount_y - a_y);
//         deposit_x<X, Y>(x);
//         deposit_y<X, Y>(y);
//         let (token_lp, fee_amount): (token::Token<LPToken<X, Y>>, u64) = mint<X, Y>();
//         (a_x, a_y, token_lp, fee_amount, left_x, left_y)
//     }
//
//     public(friend) fun remove_liquidity<X, Y>(
//         sender: &signer,
//         liquidity: u64,
//     ): (u64, u64) acquires PairEventHolder {
//         let token: token::Token<LPToken<X, Y>> = token::withdraw<LPToken<X, Y>>(sender, liquidity);
//         let (token_x, token_y, fee_amount): (
//         token::Token<X>, token::Token<Y>, u64
//         ) = remove_liquidity_direct(token);
//
//         let amount_x: u64 = token::value<X>(&token_x);
//         let amount_y: u64 = token::value<Y>(&token_y);
//
//         check_or_register_coin<X>(sender);
//         check_or_register_coin<Y>(sender);
//
//         let sender_address: address = signer::address_of(sender);
//         token::deposit<X>(sender_address, token_x);
//         token::deposit<Y>(sender_address, token_y);
//
//         //event
//         let pair_event_holder: &mut PairEventHolder<X, Y> = borrow_global_mut<PairEventHolder<X, Y>>(RESOURCE_ACCOUNT);
//         event::emit_event<RemoveLiquidityEvent<X, Y>>(
//             &mut pair_event_holder.remove_liquidity,
//             RemoveLiquidityEvent<X, Y> {
//                 user: sender_address,
//                 amount_x,
//                 amount_y,
//                 liquidity,
//                 fee_amount
//             }
//         );
//
//     }
//
//     fun remove_liquidity_direct<X, Y>(
//         token: token::Token<LPToken<X, Y>>
//     ): (token::Token<X>, token::Token<Y>, u64) {
//         burn<X, Y>(token)
//     }
//
//     public(friend) fun add_swap_event<X, Y>(
//         sender: &signer,
//         amount_in_x: u64,
//         amount_in_y: u64,
//         amount_out_x: u64,
//         amount_out_y: u64
//     ) acquires PairEventHolder {
//         let sender_address: address = signer::address_of(sender);
//         add_swap_event_with_address<X, Y>(
//             sender_address,
//             amount_in_x,
//             amount_in_y,
//             amount_out_x,
//             amount_out_y
//         );
//     }
//
//     public(friend) fun add_swap_event_with_address<X, Y>(
//         sender_addr: address,
//         amount_in_x: u64,
//         amount_in_y: u64,
//         amount_out_x: u64,
//         amount_out_y: u64
//     ) acquires PairEventHolder {
//         let pair_event_holder: &mut PairEventHolder<X, Y> = borrow_global_mut<PairEventHolder<X, Y>>(RESOURCE_ACCOUNT);
//         event::emit_event<SwapEvent<X, Y>>(
//             &mut pair_event_holder.swap,
//             SwapEvent<X, Y> {
//                 user: sender_addr,
//                 amount_x_in,
//                 amount_y_in,
//                 amount_x_out,
//                 amount_y_out
//             }
//         );
//     }
//
//     // swap X to Y, X is in and Y is out
//     public(friend) fun swap_exact_x_to_y<X, Y>(
//         sender: &signer,
//         amount_in: u64,
//         to: address
//     ): u64 acquires TokenPairReserve {
//         let token: token::Token<X> = token::withdraw<X>(sender, amount_in);
//         let (token_x_out, token_y_out): (token::Token<X>, token::Token<Y>) = swap_exact_x_to_y_direct<X, Y>(token);
//         let amount_out: u64 = token::value<Y>(&token_y_out);
//         check_or_register_coin<Y>(sender);
//         token::destroy_zero(token_x_out);
//         token::deposit(to, token_y_out);
//         amount_out
//     }
//
//     public(friend) fun swap_exact_x_to_y_direct<X, Y>(
//         token_in: token::Token<X>
//     ): (token::Token<X>, token::Token<Y>) acquires TokenPairReserve {
//         let amount_in: u64 = token::value<X>(&token_in);
//         deposit_x<X, Y>(token_in);
//
//         let (reverse_in, reverse_out, _): (u64, u64, u64) = token_reverse<X, Y>();
//         let amount_out: u64 = swap_untils::get_amount_out(amount_in, reverse_in, reverse_out);
//         let (token_x_out, token_y_out): (
//             token::Token<X>, token::Token<Y>
//         ) = swap<X, Y>(0, amount_out);
//         assert!(token::value<X>(&token_x_out) == 0, EINSUFFICIENT_OUTPUT_AMOUNT);
//         (token_x_out, token_y_out)
//     }
//
//     public(friend) fun swap_x_to_exact_y<X, Y>(
//         sender: &signer,
//         amount_in: u64,
//         amount_out: u64,
//         to: address
//     ): u64 {
//         let token_in: token::Token<X> = token::withdraw<X>(sender, amount_in);
//         let (token_x_out, token_y_out): (
//             token::Token<X>, token::Token<Y>
//         ) = swap_x_to_exact_y_direct<X, Y>(token_in, amount_out);
//         check_or_register_coin<Y>(sender);
//         token::destroy_zero(token_x_out);
//         token::deposit(to, token_y_out);
//         amount_in
//     }
//
//     public(friend) fun swap_x_to_exact_y_direct<X, Y>(
//         token_in: token::Token<X>,
//         amount_out: u64
//     ): (token::Token<X>, token::Token<Y>) {
//         deposit_x<X, Y>(token_in);
//         let (token_x_out, token_y_out) = swap<X, Y>(0, amount_out);
//         assert!(token::value<X>(&token_x_out) == 0, EINSUFFICIENT_OUTPUT_AMOUNT);
//         (token_x_out, token_y_out)
//     }
//
//     // swap Y to X, Y is in and X is out
//     public(friend) fun swap_exact_y_to_x<X, Y>(
//         sender: &signer,
//         amount_in: u64,
//         to: address
//     ): u64 acquires TokenPairReserve {
//         let token: token::Token<Y> = token::withdraw<Y>(sender, amount_in);
//         let (token_x_out, token_y_out): (token::Token<X>, token::Token<Y>) = swap_exact_y_to_x_direct<X, Y>(token);
//         let amount_out: u64 = token::value<X>(&token_x_out);
//         check_or_register_coin<X>(sender);
//         token::destroy_zero(token_y_out);
//         token::deposit(to, token_x_out);
//         amount_out
//     }
//
//     public(friend) fun swap_exact_y_to_x_direct<X, Y>(
//         token_in: token::Token<Y>
//     ): (token::Token<X>, token::Token<Y>) acquires TokenPairReserve {
//         let amount_in: u64 = token::value<Y>(&token_in);
//         deposit_y<X, Y>(token_in);
//
//         let (reverse_out, reverse_in, _): (u64, u64, u64) = token_reverse<X, Y>();
//         let amount_out: u64 = swap_untils::get_amount_out(amount_in, reverse_in, reverse_out);
//         let (token_x_out, token_y_out): (
//             token::Token<X>, token::Token<Y>
//         ) = swap<X, Y>(amount_out, 0);
//         assert!(token::value<Y>(&token_y_out) == 0, EINSUFFICIENT_OUTPUT_AMOUNT);
//         (token_x_out, token_y_out)
//     }
//
//     public(friend) fun swap_y_to_exact_x<X, Y>(
//         sender: signer,
//         amount_in: u64,
//         amount_out: u64,
//         to: address
//     ): u64 {
//
//     }
//
//     public(friend) fun swap_y_to_exact_x_direct<X, Y>(
//         token_in: token::Token<Y>,
//         amount_out: u64
//     ): (token::Token<X>, token::Token<Y>) {
//         deposit_y<X, Y>(token_in);
//         let (token_x_out, token_y_out) = swap<X, Y>(amount_out, 0);
//         assert!(token::value<Y>(&token_y_out) == 0, EINSUFFICIENT_OUTPUT_AMOUNT);
//         (token_x_out, token_y_out)
//     }
//
//     fun swap<X, Y> (
//         amount_in: u64,
//         amount_out: u64
//     ): (token::Token<X>, token::Token<Y>) {
//
//     }
//
//     fun mint<X, Y>(): (token::Token<LPToken<X, Y>>, u64) {
//
//     }
//
//     fun burn<X, Y>(
//         lp_token: token::Token<LPToken<X, Y>>
//     ): (token::Token<X>, token::Token<Y>, u64) {
//
//     }
//
//     fun updata<X, Y>(
//         balance_x:u64,
//         balance_y: u64,
//         reverse: &mut TokenPairReserve<X, Y>
//     ) {
//
//     }
//
//     fun mint_lp_to<X, Y>(
//         to: address,
//         amount: u64,
//         mint_cap: token::MintCapability<LPToken<X, Y>>
//     ) {
//
//     }
//
//     fun mint_lp<X, Y>(
//         amount: u64,
//         mint_cap: token::MintCapability<LPToken<X, Y>>
//     ) {
//
//     }
//
//     fun deposit_x<X, Y>(
//         amount: token::Token<X>
//     ) {
//
//     }
//
//     fun deposit_y<X, Y>(
//         amount: token::Token<Y>
//     ) {
//
//     }
//
//     fun extract_x<X, Y>(
//         amount: u64,
//         metadata: &mut TokenPairMetadata<X, Y>
//     ): token::Token<X> {
//
//     }
//
//     fun extract_y<X, Y>(
//         amount: u64,
//         metadata: &mut TokenPairMetadata<X, Y>
//     ): token::Token<Y> {
//
//     }
//
//     fun mint_fee<X, Y>(
//         reverse_x: u64,
//         reverse_y: u64,
//         metadata: &mut TokenPairMetadata<X, Y>
//     ): u64 {
//
//     }
//
//
//     /***********/
//     /*  */
//     public entry fun set_admin(
//         sender: &signer,
//         new_admin: address
//     ) acquires SwapInfo {
//         let sender_address: address = signer::address_of(sender);
//         let swap_info: &SwapInfo = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
//         assert!(sender_address == swap_info.admin, ENOT_ADMIN);
//         swap_info.admin = new_admin;
//     }
//
//     public entry fun set_fee_to(
//         sender: &signer,
//         new_fee_to: address
//     ) acquires SwapInfo {
//         let sender_address: address = signer::address_of(sender);
//         let swap_info: &SwapInfo = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
//         assert!(sender_address == swap_info.admin, ENOT_ADMIN);
//         swap_info.fee_to = new_fee_to;
//     }
//
//     public entry fun withdraw_fee<X, Y>(
//         sender: &signer
//     ) {
//
//     }
//
//     public entry fun withdraw_fee_noauth<X, Y>() {
//
//     }
//
//     spec withdraw_fee_noauth {
//
//     }
//
//     public entry fun upgrade_swap(
//         sender: &signer,
//         metadata_serialize: vector<u8>,
//         code: vector<vector<u8>>
//     ) {
//
//     }
//
//
//
// }