module swap::swap_pool {
    /***********/
    /* library */
    /***********/
    use std::option;
    use std::option::Option;
    use std::signer;
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
    use aptos_framework::timestamp;
    use swap::math;
    use aptos_std::math128;
    use swap::swap_utils;
    use swap::swap_utils::{PairAsset};

    friend swap::router;

    /************/
    /* constant */
    /************/
    const ZERO_ACCOUNT: address = @zero;
    const DEFAULT_ADMIN: address = @admin;
    const DEV: address = @dev;
    const ADDRESS_POOL: address = @swap;
    const USER: address = @user;

    const LP_DECIMALS: u8 = 8;
    const MINIMUM_LIQUIDITY: u128 = 10;
    const PRECISION: u128 = 10000;
    const FEE: u128 = 25;
    // 0.25%
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    const SYMBOL_POOL: vector<u8> = b"Pool";

    // Error when creating an asset pair with the same fungible asset
    const ERROR_SAME_FUNGIBLE_ASSET: u64 = 1;
    // Error when creating an asset pair that already exists
    const ERROR_PAIR_ASSET_ALREADY_EXISTS: u64 = 2;
    //Error when storing: user does not have sufficient balance
    const ERROR_SUFFICIENT_AMOUNT: u64 = 4;
    //Error when minting: insufficient liquidity
    const ERROR_SUFFICIENT_LIQUIDITY_MINTED: u64 = 6;
    // Error when burning: insufficient liquidity
    const ERROR_SUFFICIENT_LIQUIDITY_BURNED: u64 = 7;

    const ERROR_SUFFICIENT_OUTPUT_AMOUNT: u64 = 8;
    const ERROR_SUFFICIENT_INPUT_AMOUNT: u64 = 9;
    const ERROR_SUFFICIENT_LIQUIDITY: u64 = 10;
    const ERROR_SWAP: u64 = 11;

    /**********/
    /* struct */
    /**********/
    // struct containing metadata information
    struct TokenPairMetadata has store, drop {
        creator: address,
        store_fee: Object<FungibleStore>,
        k_last: u128,
        balance_x: u64,
        balance_y: u64,
    }

    // struct containing reserve information
    struct TokenPairReserve has store, drop {
        reserve_x: u64,
        reserve_y: u64,
        block_timestamp_last: u64
    }

    // struct contain list of LP Token holders
    // struct OwnerLP has key {
    //     list_owner: SmartTable<address, Object<FungibleStore>>,
    // }

    // struct containg default
    struct SwapInfo has key {
        signer_cap: SignerCapability,
        admin: address,
        addr_resource: address,
    }

    // A struct that maps an LP token address to its metadata and reserve pair
    struct GlobalPool has key {
        metadata_lp: SmartTable<PairAsset, TokenPairMetadata>,
        reserve_lp: SmartTable<PairAsset, TokenPairReserve>,
        // owner_lp: SmartTable<PairAsset, OwnerLP>
    }

    // A struct to manage minting and burning activities
    struct Management has key {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
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

    /* Main function */
    /* init function */
    fun init_module(admin: &signer) {
        let (resource_addr, signer_cap) = account::create_resource_account(admin, SYMBOL_POOL);
        let pool_signer: signer = account::create_signer_with_capability(&signer_cap);

        move_to(
            admin,
            SwapInfo {
                signer_cap,
                admin: DEFAULT_ADMIN,
                addr_resource: signer::address_of(&resource_addr)
            }
        );

        move_to(
            &pool_signer,
            GlobalPool {
                metadata_lp: smart_table::new<PairAsset, TokenPairMetadata>(),
                reserve_lp: smart_table::new<PairAsset, TokenPairReserve>(),
                // owner_lp: smart_table::new<PairAsset, OwnerLP>()
            }
        );
    }

    // Create a swap pool from 2 FA addresses
    public fun create_pair(
        creator: &signer,
        addr_fa_x: address,
        addr_fa_y: address
    ) acquires SwapInfo, GlobalPool {
        // Check whether the 2 FA assets are the same
        assert!(addr_fa_x != addr_fa_y, ERROR_SAME_FUNGIBLE_ASSET);

        // Check whether that pair already exists


        let pair_asset: PairAsset = if(swap_utils::compare_symbol_fa(addr_fa_x, addr_fa_y)) {
            swap_utils::make_pair_asset(addr_fa_x, addr_fa_y)
        } else swap_utils::make_pair_asset(addr_fa_y, addr_fa_x);

        assert!(
            !(exists_pa(pair_asset)),
            ERROR_PAIR_ASSET_ALREADY_EXISTS
        );

        let symbol_lp: vector<u8> = get_symbol_pair_asset(addr_fa_x, addr_fa_y);
        let name_lp: vector<u8> = get_name_pair_asset(addr_fa_x, addr_fa_y);
        let addr_lp: address = get_addr_fa_from_symbol(symbol_lp);
        let addr_creator: address = signer::address_of(creator);

        let swap_info: &SwapInfo = borrow_global<SwapInfo>(ADDRESS_POOL);
        let pool_signer: signer = account::create_signer_with_capability(&swap_info.signer_cap);

        let constructor_ref: &ConstructorRef = &object::create_named_object(&pool_signer, symbol_lp);
        let user_signer: signer = object::generate_signer(constructor_ref);

        // Create LP token following the FA standard
        swap_utils::init_LP(
            constructor_ref,
            option::none(),
            name_lp,
            symbol_lp,
            LP_DECIMALS,
            b"",
            b""
        );
        // update information to GlobalState
        swap_utils::add_fa_map(symbol_lp, addr_lp);
        swap_utils::add_lp_map(symbol_lp, addr_lp);
        swap_utils::add_pool_map(pair_asset, addr_lp);

        let metadata_lp: Object<Metadata> = swap_utils::get_obj_metadata_fa(addr_lp);

        let token_pair_reserve: TokenPairReserve = TokenPairReserve {
            reserve_x: 0,
            reserve_y: 0,
            block_timestamp_last: 0
        };

        // fee_amount can be assigned to a common address
        let token_pair_metadata: TokenPairMetadata = TokenPairMetadata {
            creator: addr_creator,
            store_fee: primary_fungible_store::ensure_primary_store_exists(
                addr_lp,
                metadata_lp
            ),
            k_last: 0,
            balance_x: 0,
            balance_y: 0,
        };

        let global_pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(get_addr_resource());
        global_pool.metadata_lp.add(pair_asset, token_pair_metadata);
        global_pool.reserve_lp.add(pair_asset, token_pair_reserve);

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
                user: addr_creator,
                pair_asset
            }
        )
    }

    /****************/
    /* Get Function */
    /****************/
    // Get the asset balance from the account address
    public fun get_balance(
        addr_fa: address,
        addr_account: address,
    ): u64 {
        let fa_metadata: Object<Metadata> = swap_utils::get_obj_metadata_fa(addr_fa);
        primary_fungible_store::balance(addr_account, fa_metadata)
    }

    // Get the total supply of an asset (used for LP tokens)
    public fun get_total_supply(
        addr_fa: address
    ): u128 {
        let metadata_fa: Object<Metadata> = swap_utils::get_obj_metadata_fa(addr_fa);
        let supply: Option<u128> = fungible_asset::supply(metadata_fa);
        if (supply.is_none()) {
            return 0
        } else supply.extract()
    }

    // Get reserve information of a token pair
    public fun get_token_pair_reserve(pair_asset: PairAsset): (u64, u64, u64) acquires SwapInfo, GlobalPool {
        let token_pair_reserve: &mut TokenPairReserve = borrow_global_mut<GlobalPool>(
            get_addr_resource()
        ).reserve_lp.borrow_mut(
            pair_asset
        );
        (
            token_pair_reserve.reserve_x,
            token_pair_reserve.reserve_y,
            token_pair_reserve.block_timestamp_last
        )
    }

    // Get balance information of a token pair
    public fun get_token_pair_metadata(pair_asset: PairAsset): (u64, u64) acquires GlobalPool, SwapInfo {
        let token_pair_asset: &mut TokenPairMetadata = borrow_global_mut<GlobalPool>(
            get_addr_resource()
        ).metadata_lp.borrow_mut(
            pair_asset
        );
        (
            token_pair_asset.balance_x,
            token_pair_asset.balance_y
        )
    }

    // get address admin (who init module)
    public fun get_admin(): address acquires SwapInfo {
        borrow_global<SwapInfo>(ADDRESS_POOL).admin
    }

    // get symbol of pair
    public fun get_symbol_pair_asset(addrA: address, addrB: address): vector<u8> {
        let symbol_LP: vector<u8> = b"LP-";
        let symbol_A: vector<u8> = *swap_utils::get_symbol_fa(addrA).bytes();
        let symbol_B: vector<u8> = *swap_utils::get_symbol_fa(addrB).bytes();
        symbol_LP.append(symbol_A);
        symbol_LP.append(b"-");
        symbol_LP.append(symbol_B);
        symbol_LP
    }

    // get name of pair
    public fun get_name_pair_asset(addrA: address, addrB: address): vector<u8> {
        let symbol_LP: vector<u8> = b"LP-";
        let symbol_A: vector<u8> = *swap_utils::get_name_fa(addrA).bytes();
        let symbol_B: vector<u8> = *swap_utils::get_name_fa(addrB).bytes();
        symbol_LP.append(symbol_A);
        symbol_LP.append(b"-");
        symbol_LP.append(symbol_B);
        symbol_LP
    }

    // Retrieve a certain amount of FA assets from the sender's Store
    fun get_fa_from_store_sender(sender: &signer, addr_fa: address, amount: u64): FungibleAsset {
        let store_sender: Object<FungibleStore> = primary_fungible_store::primary_store(
            signer::address_of(sender),
            swap_utils::get_obj_metadata_fa(addr_fa)
        );
        fungible_asset::withdraw(
            sender,
            store_sender,
            amount
        )
    }

    // get resource address (save in SwapInfo when init)
    public fun get_addr_resource(): address acquires SwapInfo {
        borrow_global<SwapInfo>(ADDRESS_POOL).addr_resource
    }

    // Get the address storing the information of a token pair from a resource address and symbol pair
    public fun get_addr_fa_from_symbol(symbol_fa: vector<u8>): address acquires SwapInfo {
        object::create_object_address(&get_addr_resource(), symbol_fa)
    }

    /*******************/
    /* exists function */
    /*******************/

    /* exists function */
    public fun exists_management(addr_user: address): bool {
        exists<Management>(addr_user)
    }

    public fun exists_swap_info(): bool {
        exists<SwapInfo>(ADDRESS_POOL)
    }

    public fun exists_global_pool(): bool acquires SwapInfo {
        exists<GlobalPool>(get_addr_resource())
    }

    public fun exists_pa(pa: PairAsset): bool acquires GlobalPool, SwapInfo {
        let metadata_lp: &SmartTable<PairAsset, TokenPairMetadata> = &borrow_global<GlobalPool>(
            get_addr_resource()
        ).metadata_lp;
        metadata_lp.contains(pa)
    }

    public fun exists_pair_asset(addrA: address, addrB: address): bool acquires GlobalPool, SwapInfo {
        let paAB: PairAsset = swap_utils::make_pair_asset(addrA, addrB);
        let paBA: PairAsset = swap_utils::make_pair_asset(addrB, addrA);
        // swap_utils::exists_pair_asset(paAB) || swap_utils::exists_pair_asset(paBA)
        exists_pa(paAB) || exists_pa(paBA)
    }

    /*******************/
    /* assert function */
    /*******************/
    // Check if the user has enough balance for a specific asset
    fun assert_not_enough_amount(addr_sender: address, addr_fa: address, amount: u64) {
        let metadata_fa: Object<Metadata> = swap_utils::get_obj_metadata_fa(addr_fa);
        let balance: u64 = primary_fungible_store::balance(addr_sender, metadata_fa);
        assert!(balance >= amount, ERROR_SUFFICIENT_AMOUNT);
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
    ): (u64, u64, u64) acquires SwapInfo, GlobalPool, Management {
        // ensure valid input amount
        assert!(amount_x > 0 && amount_y > 0, ERROR_SUFFICIENT_AMOUNT);

        let addr_sender: address = signer::address_of(sender);
        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let (addr_x, addr_y): (address, address) = swap_utils::get_addr_fa_x_y(pair_asset);

        assert_not_enough_amount(addr_sender, addr_x, amount_x);
        assert_not_enough_amount(addr_sender, addr_y, amount_y);

        // ensure the sender has sufficient amount
        let (
            amount_added_x,
            amount_added_y,
            liquidity,
            amount_fee
        ) = add_liquidity_direct(pair_asset, amount_x, amount_y);

        // Transfer the pre-calculated amount from the sender to the pool
        swap_utils::transfer_asset_from_to(
            addr_sender,
            addr_pa,
            addr_x,
            amount_added_x
        );
        swap_utils::transfer_asset_from_to(
            addr_sender,
            addr_pa,
            addr_y,
            amount_added_y
        );

        // pool transfer LP token to sender
        mint_lp_to(pair_asset, addr_sender, liquidity);

        event::emit(AddLiquidityEvent {
            user: addr_sender,
            pair_asset,
            amount_x,
            amount_y,
            liquidity,
            fee_amount: amount_fee,
        });
        (amount_added_x, amount_added_y, liquidity)
    }

    fun add_liquidity_direct(
        pair_asset: PairAsset,
        amount_x: u64,
        amount_y: u64
    ): (u64, u64, u64, u64) acquires SwapInfo, GlobalPool, Management {
        let pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(get_addr_resource());

        let token_pair_metadata: &mut TokenPairMetadata = pool.metadata_lp.borrow_mut(pair_asset);
        let token_pair_reserve: &mut TokenPairReserve = pool.reserve_lp.borrow_mut(pair_asset);

        let (reserve_x, reserve_y): (u64, u64) = (token_pair_reserve.reserve_x, token_pair_reserve.reserve_y);

        let (amount_added_x, amount_added_y): (u64, u64) = if (reserve_x == 0 && reserve_y == 0) {
            (amount_x, amount_y)
        } else {
            let amount_y_optimal: u64 = math::quote_y(amount_x, reserve_x, reserve_y);
            if (amount_y_optimal <= amount_y) {
                (amount_x, amount_y_optimal)
            } else {
                let amount_x_optimal: u64 = math::quote_x(amount_y, reserve_x, reserve_y);
                assert!(amount_x_optimal <= amount_x, ERROR_SUFFICIENT_AMOUNT);
                (amount_x_optimal, amount_y)
            }
        };

        assert!(amount_added_x <= amount_x, ERROR_SUFFICIENT_AMOUNT);
        assert!(amount_added_y <= amount_y, ERROR_SUFFICIENT_AMOUNT);

        // Update the balance inside the pool
        deposit_x_y(token_pair_metadata, amount_added_x, amount_added_y);

        let (amount_token_lp, amount_fee): (u64, u64) = mint_liquidity(
            pair_asset,
            token_pair_reserve,
            token_pair_metadata
        );

        (amount_added_x, amount_added_y, amount_token_lp, amount_fee)
    }

    public(friend) fun remove_liquidity(
        sender: &signer,
        pair_asset: PairAsset,
        liquidity: u64
    ): (u64, u64) acquires GlobalPool, SwapInfo, Management {
        assert!(liquidity > 0, ERROR_SUFFICIENT_AMOUNT);

        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let addr_sender: address = signer::address_of(sender);
        let (addr_x, addr_y): (address, address) = swap_utils::get_addr_fa_x_y(pair_asset);

        assert_not_enough_amount(addr_pa, addr_pa, liquidity);

        let (
            amount_x,
            amount_y,
            amount_fee
        ): (u64, u64, u64) = remove_liquidity_direct(pair_asset, liquidity);

        swap_utils::transfer_asset_from_to(
            addr_pa,
            addr_sender,
            addr_x,
            amount_x
        );
        swap_utils::transfer_asset_from_to(
            addr_pa,
            addr_sender,
            addr_y,
            amount_y
        );

        // burn amount liquidity from sender (use burn_ref of pool)
        burn_lp_from(pair_asset, addr_sender, liquidity);

        // event
        event::emit(RemoveLiquidityEvent {
            user: addr_sender,
            pair_asset,
            amount_x,
            amount_y,
            liquidity,
            fee_amount: amount_fee,
        });
        (amount_x, amount_y)
    }

    fun remove_liquidity_direct(
        pair_asset: PairAsset,
        liquidity: u64
    ): (u64, u64, u64) acquires GlobalPool, SwapInfo {
        let pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(get_addr_resource());

        let token_pair_metadata: &mut TokenPairMetadata = pool.metadata_lp.borrow_mut(pair_asset);
        let token_pair_reserve: &mut TokenPairReserve = pool.reserve_lp.borrow_mut(pair_asset);
        burn_liquidity(pair_asset, liquidity, token_pair_reserve, token_pair_metadata)
    }

    // update balance x, y when add liquidity
    fun deposit_x_y(
        token_pair_metadata: &mut TokenPairMetadata,
        amount_x: u64,
        amount_y: u64
    ) {
        token_pair_metadata.balance_x += amount_x;
        token_pair_metadata.balance_y += amount_y;
    }

    fun deposit_x(
        token_pair_metadata: &mut TokenPairMetadata,
        amount_x: u64,
    ) {
        token_pair_metadata.balance_x += amount_x;
    }

    fun deposit_y(
        token_pair_metadata: &mut TokenPairMetadata,
        amount_y: u64
    ) {
        token_pair_metadata.balance_y += amount_y;
    }

    // update balance x, y when remove liquidity
    fun extract_x_y(
        token_pair_metadata: &mut TokenPairMetadata,
        amount_x: u64,
        amount_y: u64
    ) {
        token_pair_metadata.balance_x -= amount_x;
        token_pair_metadata.balance_y -= amount_y;
    }

    fun extract_x(
        token_pair_metadata: &mut TokenPairMetadata,
        amount_x: u64,
    ) {
        token_pair_metadata.balance_x -= amount_x;
    }

    fun extract_y(
        token_pair_metadata: &mut TokenPairMetadata,
        amount_y: u64
    ) {
        token_pair_metadata.balance_y -= amount_y;
    }

    // Calculate the amount of LP tokens to be minted for the sender and the fee recipient (fee_to)
    fun mint_liquidity(
        pair_asset: PairAsset,
        token_pair_reserve: &mut TokenPairReserve,
        token_pair_metadata: &mut TokenPairMetadata
    ): (u64, u64) acquires Management {
        let (balance_x, balance_y): (u64, u64) = (token_pair_metadata.balance_x, token_pair_metadata.balance_y);
        let (reserve_x, reserve_y): (u64, u64) = (token_pair_reserve.reserve_x, token_pair_reserve.reserve_y);

        // It needs to be recalculated due to the updated balance
        // Since the reserver isn't updated together with the balance, calculations here would be inaccurate
        let amount_x: u128 = (balance_x as u128) - (reserve_x as u128);
        let amount_y: u128 = (balance_y as u128) - (reserve_y as u128);

        // Calculate the fee in the case a new pool is added, the liquidity pool will have a certain amount of LP Tokens
        let amount_fee: u64 = calculate_and_mint_fee(pair_asset, token_pair_metadata);

        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let total_supply: u128 = get_total_supply(addr_pa);

        let amount_transfer_lp: u128 = if (total_supply == 0u128) {
            let amount_total_lp: u128 = math128::sqrt(amount_x * amount_y);
            assert!(amount_total_lp > MINIMUM_LIQUIDITY, ERROR_SUFFICIENT_LIQUIDITY_MINTED);
            // When liquidity is first added, the pool is automatically minted with MINIMUM_LIQUIDITY
            mint_lp_to(
                pair_asset,
                swap_utils::get_addr_pair_asset(pair_asset),
                (MINIMUM_LIQUIDITY as u64)
            );
            amount_total_lp - MINIMUM_LIQUIDITY
        } else {
            let liquidity: u128 = math128::min(
                amount_x * total_supply / (reserve_x as u128),
                amount_y * total_supply / (reserve_y as u128)
            );
            assert!(liquidity > 0, ERROR_SUFFICIENT_LIQUIDITY_MINTED);
            liquidity
        };

        // Removing it means no fee is charged during minting
        // transfer_lp_to_store(pair_asset, token_pair_metadata.store_fee, amount_fee);

        update(
            token_pair_reserve,
            token_pair_metadata
        );
        ((amount_transfer_lp as u64), amount_fee)
    }

    // // Calculate the amount of asset to transfer to the sender and mint to the fee recipient (fee_to)
    fun burn_liquidity(
        pair_asset: PairAsset,
        liquidity: u64,
        token_pair_reserve: &mut TokenPairReserve,
        token_pair_metadata: &mut TokenPairMetadata
    ): (u64, u64, u64) {
        let (balance_x, balance_y): (u64, u64) = (token_pair_metadata.balance_x, token_pair_metadata.balance_y);

        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let total_lp_supply: u128 = get_total_supply(addr_pa);

        let amount_x: u64 = ((balance_x as u128) * (liquidity as u128) / (total_lp_supply) as u64);
        let amount_y: u64 = ((balance_y as u128) * (liquidity as u128) / (total_lp_supply) as u64);
        assert!(amount_x > 0 && amount_y > 0, ERROR_SUFFICIENT_LIQUIDITY_BURNED);

        extract_x_y(token_pair_metadata, amount_x, amount_y);

        let amount_fee: u64 = calculate_and_mint_fee(pair_asset, token_pair_metadata);
        // Removing it means no fee is charged during burning
        // transfer_lp_to_store(pair_asset, token_pair_metadata.store_fee, amount_fee);

        update(
            token_pair_reserve,
            token_pair_metadata
        );

        (amount_x, amount_y, amount_fee)
    }

    // swap X to Y
    public(friend) fun swap_exact_x_to_y(
        sender: &signer,
        pair_asset: PairAsset,
        amount_x_in: u64
    ) acquires GlobalPool, SwapInfo {
        let addr_sender: address = signer::address_of(sender);
        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let (addr_x, addr_y): (address, address) = swap_utils::get_addr_fa_x_y(pair_asset);
        assert_not_enough_amount(
            addr_sender,
            addr_x,
            amount_x_in
        );
        let amount_y_out: u64 = swap_exact_x_to_y_direct(pair_asset, amount_x_in);
        swap_utils::transfer_asset_from_to(
            addr_sender,
            addr_pa,
            addr_x,
            amount_x_in
        );
        swap_utils::transfer_asset_from_to(
            addr_pa,
            addr_sender,
            addr_y,
            amount_y_out
        );

        event::emit(
            SwapEvent {
                user: signer::address_of(sender),
                pair_asset,
                amount_x_in,
                amount_y_in: 0,
                amount_x_out: 0,
                amount_y_out,
            }
        );
    }

    public(friend) fun swap_exact_x_to_y_direct(
        pair_asset: PairAsset,
        amount_x_in: u64
    ): u64 acquires GlobalPool, SwapInfo {
        let pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(get_addr_resource());
        let token_pair_metadata: &mut TokenPairMetadata = pool.metadata_lp.borrow_mut(pair_asset);
        let token_pair_reserve: &mut TokenPairReserve = pool.reserve_lp.borrow_mut(pair_asset);

        deposit_x(token_pair_metadata, amount_x_in);
        let amount_y_out: u64 = math::get_amount_out(
            amount_x_in,
            token_pair_reserve.reserve_x,
            token_pair_reserve.reserve_y
        );
        swap(
            token_pair_metadata,
            token_pair_reserve,
            0,
            amount_y_out
        );
        amount_y_out
    }

    public(friend) fun swap_x_to_exact_y(
        sender: &signer,
        pair_asset: PairAsset,
        amount_y_out: u64
    ) acquires GlobalPool, SwapInfo {
        let addr_sender: address = signer::address_of(sender);
        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let (addr_x, addr_y): (address, address) = swap_utils::get_addr_fa_x_y(pair_asset);

        let amount_x_in: u64 = swap_x_to_exact_y_direct(pair_asset, amount_y_out);
        assert_not_enough_amount(
            addr_sender,
            addr_x,
            amount_x_in
        );
        swap_utils::transfer_asset_from_to(
            addr_sender,
            addr_pa,
            addr_x,
            amount_x_in
        );
        swap_utils::transfer_asset_from_to(
            addr_pa,
            addr_sender,
            addr_y,
            amount_y_out
        );
        event::emit(
            SwapEvent {
                user: signer::address_of(sender),
                pair_asset,
                amount_x_in,
                amount_y_in: 0,
                amount_x_out: 0,
                amount_y_out,
            }
        );
    }

    public(friend) fun swap_x_to_exact_y_direct(
        pair_asset: PairAsset,
        amount_y_out: u64
    ): u64 acquires GlobalPool, SwapInfo {
        let pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(get_addr_resource());
        let token_pair_metadata: &mut TokenPairMetadata = pool.metadata_lp.borrow_mut(pair_asset);
        let token_pair_reserve: &mut TokenPairReserve = pool.reserve_lp.borrow_mut(pair_asset);

        let amount_x_in: u64 = math::get_amount_in(
            amount_y_out,
            token_pair_reserve.reserve_x,
            token_pair_reserve.reserve_y
        );
        deposit_x(token_pair_metadata, amount_x_in);
        swap(
            token_pair_metadata,
            token_pair_reserve,
            0,
            amount_y_out
        );
        amount_x_in
    }

    // Swap Y to X
    // swap X to Y
    public(friend) fun swap_exact_y_to_x(
        sender: &signer,
        pair_asset: PairAsset,
        amount_y_in: u64
    ) acquires GlobalPool, SwapInfo {
        let addr_sender: address = signer::address_of(sender);
        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let (addr_x, addr_y): (address, address) = swap_utils::get_addr_fa_x_y(pair_asset);
        assert_not_enough_amount(
            addr_sender,
            addr_y,
            amount_y_in
        );
        let amount_x_out: u64 = swap_exact_y_to_x_direct(pair_asset, amount_y_in);
        swap_utils::transfer_asset_from_to(
            addr_sender,
            addr_pa,
            addr_y,
            amount_y_in
        );
        swap_utils::transfer_asset_from_to(
            addr_pa,
            addr_sender,
            addr_x,
            amount_x_out
        );
        event::emit(
            SwapEvent {
                user: signer::address_of(sender),
                pair_asset,
                amount_x_in: 0,
                amount_y_in,
                amount_x_out,
                amount_y_out: 0,
            }
        );
    }

    public(friend) fun swap_exact_y_to_x_direct(
        pair_asset: PairAsset,
        amount_y_in: u64
    ): u64 acquires GlobalPool, SwapInfo {
        let pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(get_addr_resource());
        let token_pair_metadata: &mut TokenPairMetadata = pool.metadata_lp.borrow_mut(pair_asset);
        let token_pair_reserve: &mut TokenPairReserve = pool.reserve_lp.borrow_mut(pair_asset);

        deposit_y(token_pair_metadata, amount_y_in);
        let amount_x_out: u64 = math::get_amount_out(
            amount_y_in,
            token_pair_reserve.reserve_y,
            token_pair_reserve.reserve_x

        );
        swap(
            token_pair_metadata,
            token_pair_reserve,
            amount_x_out,
            0
        );
        amount_x_out
    }

    public(friend) fun swap_y_to_exact_x(
        sender: &signer,
        pair_asset: PairAsset,
        amount_x_out: u64
    ) acquires GlobalPool, SwapInfo {
        let addr_sender: address = signer::address_of(sender);
        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let (addr_x, addr_y): (address, address) = swap_utils::get_addr_fa_x_y(pair_asset);

        let amount_y_in: u64 = swap_y_to_exact_x_direct(pair_asset, amount_x_out);
        assert_not_enough_amount(
            addr_sender,
            addr_y,
            amount_y_in
        );
        swap_utils::transfer_asset_from_to(
            addr_sender,
            addr_pa,
            addr_y,
            amount_y_in
        );
        swap_utils::transfer_asset_from_to(
            addr_pa,
            addr_sender,
            addr_x,
            amount_x_out
        );

        event::emit(
            SwapEvent {
                user: signer::address_of(sender),
                pair_asset,
                amount_x_in: 0,
                amount_y_in,
                amount_x_out,
                amount_y_out: 0,
            }
        );
    }

    public(friend) fun swap_y_to_exact_x_direct(
        pair_asset: PairAsset,
        amount_x_out: u64
    ): u64 acquires GlobalPool, SwapInfo {
        let pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(get_addr_resource());
        let token_pair_metadata: &mut TokenPairMetadata = pool.metadata_lp.borrow_mut(pair_asset);
        let token_pair_reserve: &mut TokenPairReserve = pool.reserve_lp.borrow_mut(pair_asset);

        let amount_y_in: u64 = math::get_amount_in(
            amount_x_out,
            token_pair_reserve.reserve_y,
            token_pair_reserve.reserve_x

        );
        deposit_y(token_pair_metadata, amount_y_in);
        swap(
            token_pair_metadata,
            token_pair_reserve,
            amount_x_out,
            0
        );
        amount_y_in
    }


    fun swap(
        token_pair_metadata: &mut TokenPairMetadata,
        token_pair_reserve: &mut TokenPairReserve,
        amount_x_out: u64,
        amount_y_out: u64
    ) {
        assert!(amount_x_out > 0 || amount_y_out > 0, ERROR_SUFFICIENT_OUTPUT_AMOUNT);
        assert!(
            amount_x_out < token_pair_reserve.reserve_x && amount_y_out < token_pair_reserve.reserve_y,
            ERROR_SUFFICIENT_LIQUIDITY
        );

        if (amount_x_out > 0) extract_x(token_pair_metadata, amount_x_out);
        if (amount_y_out > 0) extract_y(token_pair_metadata, amount_y_out);

        let (balance_x, balance_y): (u64, u64) = (token_pair_metadata.balance_x, token_pair_metadata.balance_y);
        let (reserve_x, reserve_y): (u64, u64) = (token_pair_reserve.reserve_x, token_pair_reserve.reserve_y);

        // amount in swap
        let amount_x_in: u64 = if (balance_x > reserve_x - amount_x_out) {
            balance_x - (reserve_x - amount_x_out)
        } else {
            0u64
        };
        let amount_y_in: u64 = if (balance_y > reserve_y - amount_y_out) {
            balance_y - (reserve_y - amount_y_out)
        } else {
            0u64
        };

        // ensure have amount_in
        assert!(amount_x_in > 0 || amount_y_in > 0, ERROR_SUFFICIENT_INPUT_AMOUNT);
        let balance_x_adjusted: u128 = (balance_x as u128) * PRECISION;
        let balance_y_adjusted: u128 = (balance_y as u128) * PRECISION;
        balance_x_adjusted -= (amount_x_in as u128) * FEE;
        balance_y_adjusted -= (amount_y_in as u128) * FEE;

        let reserve_x_adjusted: u128 = (reserve_x as u128) * PRECISION;
        let reserve_y_adjusted: u128 = (reserve_y as u128) * PRECISION;
        // print(&balance_x_adjusted);
        // print(&balance_y_adjusted);
        // print(&reserve_x_adjusted);
        // print(&reserve_y_adjusted);

        let compare_result: bool = if (
            balance_x_adjusted > 0
                && reserve_x_adjusted > 0
                && MAX_U128 / balance_x_adjusted > balance_y_adjusted
                && MAX_U128 / reserve_x_adjusted > reserve_y_adjusted
        ) {
            balance_x_adjusted * balance_y_adjusted >= reserve_x_adjusted * reserve_y_adjusted
        } else {
            let p: u256 = (balance_x_adjusted as u256) * (balance_y_adjusted as u256);
            let k: u256 = (reserve_x_adjusted as u256) * (reserve_y_adjusted as u256);
            p >= k
        };
        assert!(compare_result, ERROR_SWAP);
        update(
            token_pair_reserve,
            token_pair_metadata
        );
    }


    // alculate the fee based on changes in k
    fun calculate_and_mint_fee(
        pair_asset: PairAsset,
        token_pair_metadata: &mut TokenPairMetadata
    ): u64 {
        let k_old: u128 = math128::sqrt(token_pair_metadata.k_last);
        let k_last: u128 = math128::sqrt(
            (token_pair_metadata.balance_x as u128) * (token_pair_metadata.balance_y as u128)
        );
        let amount_k_change: u128 = if (k_old > k_last) {
            k_old - k_last
        } else {
            k_last - k_old
        };

        if (k_old > 0 && amount_k_change > 0) {
            let total_supply_lp: u128 = get_total_supply(swap_utils::get_addr_pair_asset(pair_asset));
            let numerator: u128 = total_supply_lp * amount_k_change * 8u128;
            let deiminator: u128 = k_old * 8u128 + k_last * 17u128;
            let liquidity: u128 = numerator / deiminator;
            (liquidity as u64)
        } else {
            0u64
        }
    }

    // update reserve and k_last
    fun update(
        token_pair_reserve: &mut TokenPairReserve,
        token_pair_metadata: &mut TokenPairMetadata
    ) {
        token_pair_reserve.reserve_x = token_pair_metadata.balance_x;
        token_pair_reserve.reserve_y = token_pair_metadata.balance_y;
        token_pair_reserve.block_timestamp_last = timestamp::now_seconds();
        token_pair_metadata.k_last = (token_pair_metadata.balance_x as u128) * (token_pair_metadata.balance_y as u128);
    }

    //
    public fun mint_lp_to(
        pair_asset: PairAsset,
        addr_to: address,
        amount: u64
    ) acquires Management {
        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let management: &Management = borrow_global<Management>(addr_pa);
        let mint_ref: &MintRef = &management.mint_ref;
        let store_to: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
            addr_to,
            swap_utils::get_obj_metadata_fa(addr_pa)
        );
        fungible_asset::mint_to(mint_ref, store_to, amount);
    }

    public fun burn_lp_from(
        pair_asset: PairAsset,
        addr_from: address,
        amount: u64
    ) acquires Management {
        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let management: &Management = borrow_global<Management>(addr_pa);
        let burn_ref: &BurnRef = &management.burn_ref;
        let store_from: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
            addr_from,
            swap_utils::get_obj_metadata_fa(addr_pa)
        );
        fungible_asset::burn_from(burn_ref, store_from, amount);
    }

    public fun transfer_lp_to_store(
        pair_asset: PairAsset,
        store_to: Object<FungibleStore>,
        amount: u64
    ) acquires Management {
        let addr_pa: address = swap_utils::get_addr_pair_asset(pair_asset);
        let management: &Management = borrow_global<Management>(addr_pa);
        let mint_ref: &MintRef = &management.mint_ref;
        fungible_asset::mint_to(mint_ref, store_to, amount);
    }

    #[test_only]
    public fun init_for_test_pool(creator: &signer) {
        init_module(creator);
    }

    #[test_only]
    public fun test_add_liquidity(
        sender: &signer,
        pair_asset: PairAsset,
        amount_x: u64,
        amount_y: u64
    ) acquires SwapInfo, GlobalPool, Management {
        add_liquidity(sender, pair_asset, amount_x, amount_y);
    }

    #[test_only]
    public fun test_remove_liquidity(
        sender: &signer,
        pair_asset: PairAsset,
        liquidity: u64
    ) acquires SwapInfo, GlobalPool, Management {
        remove_liquidity(sender, pair_asset, liquidity);
    }

    #[test_only]
    public fun test_swap_exact_x_to_y(
        sender: &signer,
        pair_asset: PairAsset,
        amount_x_in: u64
    ) acquires GlobalPool, SwapInfo {
        swap_exact_x_to_y(
            sender,
            pair_asset,
            amount_x_in
        );
    }

    #[test_only]
    public fun test_swap_x_to_exact_y(
        sender: &signer,
        pair_asset: PairAsset,
        amount_y_out: u64
    ) acquires GlobalPool, SwapInfo {
        swap_x_to_exact_y(
            sender,
            pair_asset,
            amount_y_out
        );
    }

    #[test_only]
    public fun test_swap_exact_y_to_x(
        sender: &signer,
        pair_asset: PairAsset,
        amount_y_in: u64
    ) acquires GlobalPool, SwapInfo {
        swap_exact_y_to_x(
            sender,
            pair_asset,
            amount_y_in
        );
    }

    #[test_only]
    public fun test_swap_y_to_exact_x(
        sender: &signer,
        pair_asset: PairAsset,
        amount_x_out: u64
    ) acquires GlobalPool, SwapInfo {
        swap_y_to_exact_x(
            sender,
            pair_asset,
            amount_x_out
        );
    }
}