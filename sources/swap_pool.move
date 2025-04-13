module swap::swap_pool {
    /***********/
    /* library */
    /***********/
    use std::option;
    use std::option::Option;
    use std::signer;
    use aptos_std::debug::print;
    use aptos_std::math128;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::account;
    use aptos_framework::account::{SignerCapability};
    use aptos_framework::event;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{FungibleStore, FungibleAsset, Metadata, MintRef, BurnRef, TransferRef};
    use aptos_framework::object;
    use aptos_framework::object::{Object, ConstructorRef};
    use aptos_framework::primary_fungible_store;
    use swap::math;
    use swap::swap_resource;
    use swap::swap_resource::{PairAsset, get_address_pair_asset, get_object_metadata, GlobalState};

    /************/
    /* constant */
    /************/
    const ZERO_ACCOUNT: address = @zero;
    const DEFAULT_ADMIN: address = @admin;
    const DEV: address = @dev;
    const ADDRESS_POOL: address = @swap;
    const USER: address = @user;

    const LP_DECIMALS: u8 = 8;
    const MINIMUM_LIQUIDITY: u128 = 1000;

    const SYMBOL_POOL: vector<u8> = b"Pool";
    const SYMBOL_USERS: vector<u8> = b"Users Management";

    const ERROR_SAME_FUNGIBLE_ASSET: u64 = 1;
    const ERROR_PAIR_ASSET_ALREADY_EXISTS: u64 = 2;
    const ERROR_NOT_ADMIN_RESOURCE: u64 = 3;
    const ERROR_ENOUT_AMOUNT: u64 = 4;
    const ERROR_SUFFICIENT_AMOUNT: u64 = 5;
    const ERROR_INPUT_AMOUNT: u64 = 6;
    const ERROR_SUFFICIENT_LIQUIDITY_MINTED: u64 = 7;
    const ERROR_SUFFICIENT_LIQUIDITY: u64 = 8;

    /**********/
    /* struct */
    /**********/
    struct TokenPairMetadata has store, drop {
        creator: address,
        fee_amount: u64,
        k_last: u128,
        balance_x: u64,
        balance_y: u64,
    }

    struct TokenPairReserve has store {
        reserve_x: u64,
        reserve_y: u64,
        block_timestamp_last: u64
    }

    struct SwapInfo has key {
        signer_cap: SignerCapability,
        fee_to: address,
        admin: address,
        addr_resource: address,
    }

    struct GlobalPool has key {
        metadata_lp: SmartTable<PairAsset, TokenPairMetadata>,
        reserve_lp: SmartTable<PairAsset, TokenPairReserve>,
    }

    #[event]
    struct PairCreatedEvent has drop, store {
        user: address,
        pair_asset: PairAsset,
    }

    #[event]
    struct AddLiquidityEvent has drop, store {
        user: address,
        pair_asset: PairAsset,
        amount_x: u64,
        amount_y: u64,
        liquidity: u64,
        fee_amount: u64,
    }

    #[event]
    struct RemoveLiquidityEvent has drop, store {
        user: address,
        pair_asset: PairAsset,
        amount_x: u64,
        amount_y: u64,
        liquidity: u64,
        fee_amount: u64,
    }

    #[event]
    struct SwapEvent has drop, store {
        user: address,
        pair_asset: PairAsset,
        amount_x_in: u64,
        amount_y_in: u64,
        amount_x_out: u64,
        amount_y_out: u64
    }

    struct Management has key {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    /* init function */
    fun init_module(admin: &signer) {
        let (resource_addr, signer_cap) = account::create_resource_account(admin, SYMBOL_POOL);
        let pool_signer: signer = account::create_signer_with_capability(&signer_cap);

        move_to(
            admin,
            SwapInfo {
                signer_cap,
                fee_to: ZERO_ACCOUNT,
                admin: DEFAULT_ADMIN,
                addr_resource: signer::address_of(&resource_addr)
            }
        );

        move_to(
            &pool_signer,
            GlobalPool {
                metadata_lp: smart_table::new<PairAsset, TokenPairMetadata>(),
                reserve_lp: smart_table::new<PairAsset, TokenPairReserve>()
            }
        );
    }

    public fun create_pair(
        creator: &signer,
        address_fa_x: address,
        address_fa_y: address
    ) acquires SwapInfo, GlobalPool {
        assert!(address_fa_x != address_fa_y, ERROR_SAME_FUNGIBLE_ASSET);
        assert!(
            !(exists_pair_asset(address_fa_x, address_fa_y)),
            ERROR_PAIR_ASSET_ALREADY_EXISTS
        );

        let symbol_lp: vector<u8> = create_symbol_pair_asset(address_fa_x, address_fa_y);
        let name_lp: vector<u8> = create_name_pair_asset(address_fa_x, address_fa_y);

        let swap_info: &SwapInfo = borrow_global<SwapInfo>(ADDRESS_POOL);
        let pool_signer: signer = account::create_signer_with_capability(&swap_info.signer_cap);

        let constructor_ref: &ConstructorRef = &object::create_named_object(&pool_signer, symbol_lp);
        let user_signer: signer = object::generate_signer(constructor_ref);

        swap_resource::init_LP(
            &pool_signer,
            constructor_ref,
            option::none(),
            name_lp,
            symbol_lp,
            LP_DECIMALS,
            b"",
            b""
        );

        // add to pool_map
        let address_lp: address = swap_resource::get_address_FA(symbol_lp);
        let pair_asset: PairAsset = swap_resource::make_pair_asset(address_fa_x, address_fa_y);
        swap_resource::add_pool_map(pair_asset, address_lp);

        let creator_address: address = signer::address_of(creator);

        // let signer_cap = resource_account::retrieve_resource_account_cap(creator, ADDRESS_POOL);

        let token_pair_reserve: TokenPairReserve = TokenPairReserve {
            reserve_x: 0,
            reserve_y: 0,
            block_timestamp_last: 0
        };

        let token_pair_metadata: TokenPairMetadata = TokenPairMetadata {
            creator: creator_address,
            fee_amount: 0,
            k_last: 0,
            balance_x: 0,
            balance_y: 0,
        };

        let global_pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(resource_address());
        global_pool.metadata_lp.add(pair_asset, token_pair_metadata);
        global_pool.reserve_lp.add(pair_asset, token_pair_reserve);

        // let user_signer: signer = object::generate_signer(&constructor_ref);
        let mint_ref: MintRef = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref: BurnRef = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref: TransferRef = fungible_asset::generate_transfer_ref(constructor_ref);

        move_to(
            &user_signer,
            Management {
                mint_ref,
                burn_ref,
                transfer_ref
            }
        );

        event::emit(
            PairCreatedEvent {
                user: creator_address,
                pair_asset
            }
        )
    }

    public fun lp_balance(
        lp_addr: address,
        account_addr: address,
    ): u64 {
        fungible_asset::balance(swap_resource::get_object_metadata(lp_addr))
        // primary_fungible_store::balance(account_addr, swap_resource::get_object_metadata(lp_addr))
    }

    public fun total_lp_supply(
        lp_addr: address
    ): u128 {
        let supply: Option<u128> = fungible_asset::supply(swap_resource::get_object_metadata(lp_addr));
        if (supply.is_none()) {
            return 0
        } else supply.extract()
    }

    public fun token_reserve(pa_lp: PairAsset): (u64, u64, u64) acquires SwapInfo, GlobalPool {
        let token_pair_reserve: &mut TokenPairReserve = borrow_global_mut<GlobalPool>(resource_address()).reserve_lp.borrow_mut(pa_lp);
        (
            token_pair_reserve.reserve_x,
            token_pair_reserve.reserve_y,
            token_pair_reserve.block_timestamp_last
        )
    }

    public fun token_balance(pa_lp: PairAsset): (u64, u64) acquires GlobalPool, SwapInfo {
        let token_pair_asset: &mut TokenPairMetadata= borrow_global_mut<GlobalPool>(resource_address()).metadata_lp.borrow_mut(pa_lp);
        (
            token_pair_asset.balance_x,
            token_pair_asset.balance_y
        )
    }

    public fun admin(): address acquires SwapInfo {
        borrow_global<SwapInfo>(ADDRESS_POOL).admin
    }

    public fun fee_to(): address acquires SwapInfo {
        borrow_global<SwapInfo>(ADDRESS_POOL).fee_to
    }

    public fun pool_address(): address {
        object::create_object_address(&ADDRESS_POOL, SYMBOL_POOL)
    }

    public fun user_address(user_addr: address, user_symbol: vector<u8>): address {
        object::create_object_address(&user_addr, user_symbol)
    }

    public fun exists_management(user_addr: address, pa: PairAsset): bool {
        let symbol: vector<u8> = *swap_resource::get_symbol(swap_resource::get_address_pair_asset(pa)).bytes();
        exists<Management>(user_address(user_addr, symbol))
    }

    public fun resource_address(): address acquires SwapInfo {
        borrow_global<SwapInfo>(ADDRESS_POOL).addr_resource
    }

    fun exists_pair_asset(addrA: address, addrB: address): bool {
        let paAB: PairAsset = swap_resource::make_pair_asset(addrA, addrB);
        let paBA: PairAsset = swap_resource::make_pair_asset(addrB, addrA);
        swap_resource::exists_pair_asset(paAB) && swap_resource::exists_pair_asset(paBA)
    }

    public fun create_symbol_pair_asset(addrA: address, addrB: address): vector<u8> {
        let symbol_LP: vector<u8> = b"LP-";
        let symbol_A: vector<u8> = *swap_resource::get_symbol(addrA).bytes();
        let symbol_B: vector<u8> = *swap_resource::get_symbol(addrB).bytes();
        symbol_LP.append(symbol_A);
        symbol_LP.append(b"-");
        symbol_LP.append(symbol_B);
        symbol_LP
    }

    public fun create_name_pair_asset(addrA: address, addrB: address): vector<u8> {
        let symbol_LP: vector<u8> = b"LP-";
        let symbol_A: vector<u8> = *swap_resource::get_name(addrA).bytes();
        let symbol_B: vector<u8> = *swap_resource::get_name(addrB).bytes();
        symbol_LP.append(symbol_A);
        symbol_LP.append(b"-");
        symbol_LP.append(symbol_B);
        symbol_LP
    }

    public fun exists_swap_info(): bool {
        exists<SwapInfo>(ADDRESS_POOL)
    }

    public fun exists_global_pool(): bool acquires SwapInfo {
        exists<GlobalPool>(resource_address())
    }


    public fun is_contain(pa: PairAsset): bool acquires GlobalPool, SwapInfo {
        let metadata_lp = &borrow_global<GlobalPool>(resource_address()).metadata_lp;
        metadata_lp.contains(pa)
    }

    //
    // fun get_asset_from_sender(sender: &signer, addr: address, amount: u64): u64 {
    //     assert_not_enough_amount(sender, addr, amount);
    //     let store: Object<FungibleStore> = primary_fungible_store::primary_store(
    //         signer::address_of(sender),
    //         swap_resource::get_object_metadata(addr)
    //     );
    //     let fa: FungibleAsset = fungible_asset::withdraw(
    //         sender,
    //         store,
    //         amount
    //     );
    //     amount
    // }

    /* assert function */
    fun assert_not_enough_amount(sender: &signer, addr_fa: address, amount: u64) {
        let sender_address: address = signer::address_of(sender);
        let metadata_fa: Object<Metadata> = swap_resource::get_object_metadata(addr_fa);
        let balance: u64 = primary_fungible_store::balance(sender_address, metadata_fa);
        assert!(balance >= amount, ERROR_ENOUT_AMOUNT);
    }

    /*******************************/
    /* add, remove liquidity, swap */
    /*******************************/
    // add liquidity in pool
    public(friend) fun add_liquidity(
        sender: &signer,
        pair_asset: PairAsset,
        amount_x: u64,
        amount_y: u64
    ) acquires SwapInfo, GlobalPool {
        // ensure valid input amount
        assert!(amount_x > 0 && amount_y > 0, ERROR_INPUT_AMOUNT);
        // ensure the sender has sufficient amount
        // assert_not_enough_amount()
        let sender_address: address = signer::address_of(sender);
        let (addr_x, addr_y): (address, address) = swap_resource::get_addres_pa_x_y(pair_asset);

        let (
            a_x,
            a_y,
            lp_amount,
            fee_amount,
            left_x,
            left_y
        ) = add_liquidity_direct(pair_asset, amount_x, amount_y);

        assert!(lp_amount > 0, ERROR_SUFFICIENT_LIQUIDITY);

        event::emit(AddLiquidityEvent {
            user: sender_address,
            pair_asset,
            amount_x,
            amount_y,
            liquidity: lp_amount,
            fee_amount,
        });
    }

    fun add_liquidity_direct(
        pair_asset: PairAsset,
        amount_x: u64,
        amount_y: u64
    ): (u64, u64, u64, u64, u64, u64) acquires SwapInfo, GlobalPool {
        let (reserve_x, reserve_y, _): (u64, u64, u64) = token_reserve(pair_asset);

        let(a_x, a_y): (u64, u64) = if (reserve_x == 0 && reserve_y == 0) {
            (amount_x, amount_y)
        } else {
            let amount_y_optimal: u64 = math::quote_y(amount_x, reserve_x, reserve_y);
            if (amount_y_optimal <= amount_y) {
                (amount_x, amount_y_optimal)
            } else {
                let amount_x_optimal: u64 = math::quote_x(amount_y, reserve_x, reserve_y);
                assert!(amount_x_optimal <= amount_x, ERROR_INPUT_AMOUNT);
                (amount_x_optimal, amount_y)
            }
        };

        assert!(a_x <= amount_x, ERROR_SUFFICIENT_AMOUNT);
        assert!(a_y <= amount_y, ERROR_SUFFICIENT_AMOUNT);

        let left_x: u64 = amount_x - a_x;
        let left_y: u64 = amount_y - a_y;

        deposit_x(pair_asset, amount_x);
        deposit_y(pair_asset, amount_y);

        let(lp_amount, fee_amount) = (0u64, 0u64);

        (a_x, a_y, lp_amount, fee_amount, left_x, left_y)
    }

    fun deposit_x(
        pair_asset: PairAsset,
        amount: u64
    ) acquires GlobalPool, SwapInfo {
        let token_pair_metadata: &mut TokenPairMetadata = borrow_global_mut<GlobalPool>(resource_address()).metadata_lp.borrow_mut(pair_asset);
        token_pair_metadata.balance_x += amount
    }

    fun deposit_y(
        pair_asset: PairAsset,
        amount: u64
    ) acquires GlobalPool, SwapInfo {
        let token_pair_metadata: &mut TokenPairMetadata = borrow_global_mut<GlobalPool>(resource_address()).metadata_lp.borrow_mut(pair_asset);
        token_pair_metadata.balance_y += amount
    }

    // fun mint(
    //     pair_asset: PairAsset,
    // ): (u64, u64) acquires GlobalPool, SwapInfo {
    //     let (balance_x, balance_y): (u64, u64) = token_balance(pair_asset);
    //     let (reserve_x, reserve_y, _): (u64, u64, u64) = token_reserve(pair_asset);
    //     let token_pair_metadata: &mut TokenPairMetadata = borrow_global_mut<GlobalPool>(resource_address()).metadata_lp.borrow_mut(pair_asset);
    //
    //     let amount_x: u128 = (balance_x as u128) - (reserve_x as u128);
    //     let amount_y: u128 = (balance_y as u128) - (reserve_y as u128);
    //
    //     let fee_amount: u64 = calculate_and_mint_fee(pair_asset, reserve_x, reserve_y, token_pair_metadata);
    //
    //     let address_lp: address = get_address_pair_asset(pair_asset);
    //     let total_supply: u128 = total_lp_supply(address_lp);
    //     let liquidity: u128 = if (total_supply == 0u128) {
    //         let lp_total_amount: u128 = math128::sqrt(amount_x * amount_y);
    //         assert!(lp_total_amount > MINIMUM_LIQUIDITY, ERROR_SUFFICIENT_LIQUIDITY_MINTED);
    //
    //         let lp_user_amount: u128 = lp_total_amount - MINIMUM_LIQUIDITY;
    //         mint_lp_to();
    //         lp_user_amount
    //     } else {
    //         let liquidity: u128 = math128::min(
    //             amount_x * total_supply / (reserve_x as u128),
    //             amount_y * total_supply / (reserve_y as u128)
    //         );
    //         assert!(liquidity > 0, ERROR_SUFFICIENT_LIQUIDITY_MINTED);
    //         liquidity
    //     };
    //
    //
    //     let lp: FungibleAsset = mint_lp((liquidity as u64), &token_pair_metadata.mint_ref);
    //     update();
    //     token_pair_metadata.k_last = (reserve_x as u128) * (reserve_y as u128);
    //     (lp, fee_amount)
    // }

    //
    // fun mint_lp(
    //     fee: u64,
    //     mint_ref: &MintRef
    // ): FungibleAsset {
    //     fungible_asset::mint(mint_ref, fee)
    // }
    //
    // fun update() {
    //
    // }
    //

    fun calculate_and_mint_fee(
        pair_asset: PairAsset,
        reserve_x: u64,
        reserve_y: u64,
        token_pair_metadata: &mut TokenPairMetadata
    ): u64 {
        let fee: u64 = 0u64;
        if (token_pair_metadata.k_last > 0) {
            let k_new: u128 = math128::sqrt((reserve_x as u128) * (reserve_y as u128));
            let k_last: u128 = token_pair_metadata.k_last;
            if (k_new > k_last) {
                let numerator: u128 = total_lp_supply(
                    get_address_pair_asset(pair_asset)
                ) * (k_new - k_last) * 8u128;
                let deiminator: u128 = k_last * 8u128 + k_new * 17u128;
                let liquidity: u128 = numerator / deiminator;
                fee = (liquidity as u64);
                // mint fee if
                if (fee > 0) {
                    token_pair_metadata.fee_amount += fee
                }
            }
        };
        fee
    }


    //
    // public fun is(): bool acquires SwapInfo {
    //     exists<Management>(resource_address())
    // }

    public fun mint_lp_to(
        pair_asset: PairAsset,
        addr_to: address,
        amount: u64
    ) acquires Management {
        let pa_addr: address = swap_resource::get_address_pair_asset(pair_asset);
        let symbol: vector<u8> = *swap_resource::get_symbol(pa_addr).bytes();

        let addr_creator: address = swap_resource::get_creator_pair_asset(symbol);
        let management: &Management = borrow_global<Management>(user_address(addr_creator, symbol));
        let mint_ref: &MintRef = &management.mint_ref;
        let store_to: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
            addr_to,
            swap_resource::get_object_metadata(pa_addr)
        );
        fungible_asset::mint_to(mint_ref, store_to, amount);
    }


    #[test_only(sender = @swap)]
    public fun init_for_test_pool(admin: &signer) {
        init_module(admin);
    }
}