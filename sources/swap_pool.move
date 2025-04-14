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
    use aptos_framework::timestamp;
    use aptos_framework::transaction_context::gas_unit_price;
    use swap::math;
    use swap::swap_utils;
    use swap::swap_utils::{PairAsset, get_address_pair_asset, get_symbol, get_address_FA};

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

    const SYMBOL_POOL: vector<u8> = b"Pool";
    const SYMBOL_USERS: vector<u8> = b"Users Management";

    const ERROR_SAME_FUNGIBLE_ASSET: u64 = 1;
    const ERROR_PAIR_ASSET_ALREADY_EXISTS: u64 = 2;
    const ERROR_NOT_ADMIN_RESOURCE: u64 = 3;
    const ERROR_ENOUT_AMOUNT: u64 = 4;
    const ERROR_SUFFICIENT_AMOUNT: u64 = 5;
    const ERROR_INPUT_AMOUNT: u64 = 6;
    const ERROR_SUFFICIENT_LIQUIDITY_MINTED: u64 = 7;
    const ERROR_SUFFICIENT_LIQUIDITY_BURNED: u64 = 8;
    const ERROR_SUFFICIENT_LIQUIDITY: u64 = 9;

    /**********/
    /* struct */
    /**********/
    // struct containing metadata information
    struct TokenPairMetadata has store, drop {
        creator: address,
        fee_amount: Object<FungibleStore>,
        k_last: u128,
        balance_x: Object<FungibleStore>,
        balance_y: Object<FungibleStore>,
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
    struct SwapInfo has key{
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
        address_fa_x: address,
        address_fa_y: address
    ) acquires SwapInfo, GlobalPool {
        // Check whether the 2 FA assets are the same
        assert!(address_fa_x != address_fa_y, ERROR_SAME_FUNGIBLE_ASSET);

        // Check whether that pair already exists
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

        // Create LP token following the FA standard
        swap_utils::init_LP(
            &user_signer,
            constructor_ref,
            option::none(),
            name_lp,
            symbol_lp,
            LP_DECIMALS,
            b"",
            b""
        );

        swap_utils::add_fa_map(symbol_lp, creator_address(symbol_lp));
        swap_utils::add_lp_map(symbol_lp, creator_address(symbol_lp));

        // add to pool_map
        let address_lp: address = swap_utils::get_address_FA(symbol_lp);

        let metadata_lp: Object<Metadata> = swap_utils::get_object_metadata(address_lp);
        let metadata_x: Object<Metadata> = swap_utils::get_object_metadata(address_fa_x);
        let metadata_y: Object<Metadata> = swap_utils::get_object_metadata(address_fa_y);

        let pair_asset: PairAsset = swap_utils::make_pair_asset(address_fa_x, address_fa_y);
        swap_utils::add_pool_map(pair_asset, address_lp);

        let creator_address: address = signer::address_of(creator);

        let token_pair_reserve: TokenPairReserve = TokenPairReserve {
            reserve_x: 0,
            reserve_y: 0,
            block_timestamp_last: 0
        };

        let addr_owner: address = creator_address(symbol_lp);

        // fee_mount, balance_x, balance_y is FungibleStore used to hold FA assets
        let token_pair_metadata: TokenPairMetadata = TokenPairMetadata {
            creator: creator_address,
            fee_amount: primary_fungible_store::ensure_primary_store_exists(
                addr_owner,
                metadata_lp
            ),
            k_last: 0,
            balance_x: primary_fungible_store::ensure_primary_store_exists(
                addr_owner,
                metadata_x
            ),
            balance_y: primary_fungible_store::ensure_primary_store_exists(
                addr_owner,
                metadata_y
            ),
        };

        let global_pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(resource_address());
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
                user: creator_address,
                pair_asset
            }
        )
    }

    /****************/
    /* Get Function */
    /****************/
    // Get the asset balance from the account address
    public fun get_balance(
        fa_addr: address,
        account_addr: address,
    ): u64 {
        let fa_metadata: Object<Metadata> = swap_utils::get_object_metadata(fa_addr);
        primary_fungible_store::balance(account_addr, fa_metadata)
    }

    // Get the total supply of an asset (used for LP tokens)
    public fun get_total_supply(
        fa_addr: address
    ): u128 {
        let fa_symbol: vector<u8> = *get_symbol(fa_addr).bytes();
        let fa_creator: address = get_address_FA(fa_symbol);
        let fa_metadata: Object<Metadata> = swap_utils::get_object_metadata(fa_creator);
        let supply: Option<u128> = fungible_asset::supply(fa_metadata);
        if (supply.is_none()) {
            return 0
        } else supply.extract()
    }

    // Get reserve information of a token pair
    public fun get_token_pair_reserve(pair_asset_lp: PairAsset): (u64, u64, u64) acquires SwapInfo, GlobalPool {
        let token_pair_reserve: &mut TokenPairReserve = borrow_global_mut<GlobalPool>(resource_address()).reserve_lp.borrow_mut(pair_asset_lp);
        (
            token_pair_reserve.reserve_x,
            token_pair_reserve.reserve_y,
            token_pair_reserve.block_timestamp_last
        )
    }

    // Get balance information of a token pair
    public fun get_token_pair_metadata(pair_asset_lp: PairAsset): (Object<FungibleStore>, Object<FungibleStore>) acquires GlobalPool, SwapInfo {
        let token_pair_asset: &mut TokenPairMetadata= borrow_global_mut<GlobalPool>(resource_address()).metadata_lp.borrow_mut(pair_asset_lp);
        (
            token_pair_asset.balance_x,
            token_pair_asset.balance_y
        )
    }

    // get address admin (who init module)
    public fun get_admin(): address acquires SwapInfo {
        borrow_global<SwapInfo>(ADDRESS_POOL).admin
    }

    // get the address receive fee
    // public fun get_fee_to(): address acquires SwapInfo {
    //     borrow_global<SwapInfo>(ADDRESS_POOL).fee_to
    // }

    // Retrieve a certain amount of FA assets from the sender's Store
    fun get_fa_from_store_sender(sender: &signer, fa_addr: address, amount: u64): FungibleAsset {
        assert_not_enough_amount(sender, fa_addr, amount);
        let store: Object<FungibleStore> = primary_fungible_store::primary_store(
            signer::address_of(sender),
            swap_utils::get_object_metadata(fa_addr)
        );
        fungible_asset::withdraw(
            sender,
            store,
            amount
        )
    }

    // Get the address storing the information of a token pair from a resource address and symbol pair
    public fun creator_address(asset_symbol: vector<u8>): address acquires SwapInfo {
        object::create_object_address(&resource_address(), asset_symbol)
    }

    // get resource address (save in SwapInfo when init)
    public fun  resource_address(): address acquires SwapInfo {
        borrow_global<SwapInfo>(ADDRESS_POOL).addr_resource
    }


    /* exists function */
    public fun exists_management(user_addr: address): bool {
        // let symbol: vector<u8> = *swap_resource::get_symbol(swap_resource::get_address_pair_asset(pa)).bytes();
        // print(&creator_address(user_addr, symbol));
        // true;
        exists<Management>(user_addr)
        // exists<Management>(creator_address(user_addr, symbol))
    }

    fun exists_pair_asset(addrA: address, addrB: address): bool {
        let paAB: PairAsset = swap_utils::make_pair_asset(addrA, addrB);
        let paBA: PairAsset = swap_utils::make_pair_asset(addrB, addrA);
        swap_utils::exists_pair_asset(paAB) || swap_utils::exists_pair_asset(paBA)
    }

    public fun create_symbol_pair_asset(addrA: address, addrB: address): vector<u8> {
        let symbol_LP: vector<u8> = b"LP-";
        let symbol_A: vector<u8> = *swap_utils::get_symbol(addrA).bytes();
        let symbol_B: vector<u8> = *swap_utils::get_symbol(addrB).bytes();
        symbol_LP.append(symbol_A);
        symbol_LP.append(b"-");
        symbol_LP.append(symbol_B);
        symbol_LP
    }

    public fun create_name_pair_asset(addrA: address, addrB: address): vector<u8> {
        let symbol_LP: vector<u8> = b"LP-";
        let symbol_A: vector<u8> = *swap_utils::get_name(addrA).bytes();
        let symbol_B: vector<u8> = *swap_utils::get_name(addrB).bytes();
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



    /*******************/
    /* assert function */
    /*******************/
    // Check if the user has enough balance for a specific asset
    fun assert_not_enough_amount(sender: &signer, fa_addr: address, amount: u64) {
        let sender_address: address = signer::address_of(sender);
        let fa_metadata: Object<Metadata> = swap_utils::get_object_metadata(fa_addr);
        let balance: u64 = primary_fungible_store::balance(sender_address, fa_metadata);
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
    ) acquires SwapInfo, GlobalPool, Management {
        // ensure valid input amount
        assert!(amount_x > 0 && amount_y > 0, ERROR_INPUT_AMOUNT);
        let (addr_x, addr_y): (address, address) = swap_utils::get_addres_fa_x_y(pair_asset);

        // ensure the sender has sufficient amount
        let fa_x: FungibleAsset = get_fa_from_store_sender(
            sender,
            addr_x,
            amount_x
        );
        let fa_y: FungibleAsset = get_fa_from_store_sender(
            sender,
            addr_y,
            amount_y
        );

        let (
            _,
            _,
            liquidity,
            amount_fee,
            remainder_x,
            remainder_y
        ) = add_liquidity_direct(sender, pair_asset, fa_x, fa_y);

        let addr_sender: address = signer::address_of(sender);
        // let addr_lp: address = swap_resource::get_address_pair_asset(pair_asset);

        let metadata_x: Object<Metadata> = swap_utils::get_object_metadata(addr_x);
        let metadata_y: Object<Metadata> = swap_utils::get_object_metadata(addr_y);

        // Ensure that the sender has a store to receive the remaining funds
        let store_sender_x: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
            addr_sender,
            metadata_x
        );
        let store_sender_y: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
            addr_sender,
            metadata_y
        );

        transfer_lp_to(pair_asset, addr_sender, liquidity);

        // Update the balances in the sender's stores
        // fee_amount will update in mint_lp_to
        fungible_asset::deposit(
            store_sender_x,
            remainder_x
        );
        fungible_asset::deposit(
            store_sender_y,
            remainder_y
        );

        event::emit(AddLiquidityEvent {
            user: addr_sender,
            pair_asset,
            amount_x,
            amount_y,
            liquidity,
            fee_amount: amount_fee,
        });
    }

    fun add_liquidity_direct(
        sender: &signer,
        pair_asset: PairAsset,
        fa_x: FungibleAsset,
        fa_y: FungibleAsset
    ): (u64, u64, u64, u64, FungibleAsset, FungibleAsset) acquires SwapInfo, GlobalPool, Management {
        let amount_x: u64 = fungible_asset::amount(&fa_x);
        let amount_y: u64 = fungible_asset::amount(&fa_y);
        let (reserve_x, reserve_y, _): (u64, u64, u64) = get_token_pair_reserve(pair_asset);

        let(amount_added_x, amount_added_y): (u64, u64) = if (reserve_x == 0 && reserve_y == 0) {
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

        assert!(amount_added_x <= amount_x, ERROR_SUFFICIENT_AMOUNT);
        assert!(amount_added_y <= amount_y, ERROR_SUFFICIENT_AMOUNT);

        let left_x: FungibleAsset = fungible_asset::extract(&mut fa_x, amount_x - amount_added_x);
        let left_y: FungibleAsset = fungible_asset::extract(&mut fa_y, amount_y - amount_added_y);


        // Update the balance inside the pool
        deposit_x(pair_asset, fa_x);
        deposit_y(pair_asset, fa_y); // trong pancake deposit x thif

        let(amount_token_lp, fee_amount) = mint(pair_asset);

        (amount_added_x, amount_added_y, amount_token_lp, fee_amount, left_x, left_y)
    }

    // public(friend) fun remove_liquidity(
    //     sender: &signer,
    //     pair_asset: PairAsset,
    //     liquidity: u64
    // ) acquires GlobalPool, SwapInfo, Management {
    //     assert!(liquidity > 0, ERROR_INPUT_AMOUNT);
    //     let addr_pa: address = swap_utils::get_address_pair_asset(pair_asset);
    //     let liquidity_token: FungibleAsset = get_fa_from_store_sender(sender, addr_pa, liquidity);
    //
    //     let (
    //         amount_x,
    //         amount_y,
    //         amount_fee
    //     ) = remove_liquidity_direct(pair_asset, liquidity);
    //
    //     let return_x: u64 = fungible_asset::amount(&amount_x);
    //     let return_y: u64 = fungible_asset::amount(&amount_y);
    //
    //     let (addr_x, addr_y): (address, address) = swap_utils::get_addres_fa_x_y(pair_asset);
    //     let addr_sender: address = signer::address_of(sender);
    //
    //     let metadata_x: Object<Metadata> = swap_utils::get_object_metadata(addr_x);
    //     let metadata_y: Object<Metadata> = swap_utils::get_object_metadata(addr_y);
    //
    //     // Ensure that the sender has a store to receive the remaining funds
    //     let store_sender_x: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
    //         addr_sender,
    //         metadata_x
    //     );
    //     let store_sender_y: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
    //         addr_sender,
    //         metadata_y
    //     );
    //
    //     // burn liquidity_token
    //
    //     // Update the balances in the sender's stores (deposit by revome liquidity)
    //     // fee_amount will update in mint_lp_to
    //     fungible_asset::deposit(
    //         store_sender_x,
    //         amount_x
    //     );
    //     fungible_asset::deposit(
    //         store_sender_y,
    //         amount_y
    //     );
    //
    //     // event
    //     event::emit(RemoveLiquidityEvent {
    //         user,
    //         pair_asset,
    //         amount_x: return_x,
    //         amount_y: return_y,
    //         liquidity,
    //         fee_amount,
    //     });
    // }
    //
    // fun remove_liquidity_direct(
    //     pair_asset: PairAsset,
    //     liquidity: u64
    // ): (FungibleAsset, FungibleAsset, u64) acquires GlobalPool, SwapInfo, Management {
    //     burn(pair_asset, liquidity)
    // }

    fun deposit_x(
        pair_asset: PairAsset,
        amount: FungibleAsset
    ) acquires GlobalPool, SwapInfo {
        let token_pair_metadata: &mut TokenPairMetadata = borrow_global_mut<GlobalPool>(resource_address()).metadata_lp.borrow_mut(pair_asset);
        fungible_asset::deposit(token_pair_metadata.balance_x, amount);
    }

    fun deposit_y(
        pair_asset: PairAsset,
        amount: FungibleAsset
    ) acquires GlobalPool, SwapInfo {
        let token_pair_metadata: &mut TokenPairMetadata = borrow_global_mut<GlobalPool>(resource_address()).metadata_lp.borrow_mut(pair_asset);
        fungible_asset::deposit(token_pair_metadata.balance_y, amount);
    }

    // fun extract_x(
    //     pair_asset: PairAsset,
    //     amount: FungibleAsset
    // ) acquires GlobalPool, SwapInfo {
    //     let token_pair_metadata: &mut TokenPairMetadata = borrow_global_mut<GlobalPool>(resource_address()).metadata_lp.borrow_mut(pair_asset);
    //     fungible_asset::deposit(token_pair_metadata.balance_x, amount);
    //     fungible_asset::;
    //     primary_fungible_store::tra
    // }

    fun extract_y(
        pair_asset: PairAsset,
        amount: FungibleAsset
    ) acquires GlobalPool, SwapInfo {
        let token_pair_metadata: &mut TokenPairMetadata = borrow_global_mut<GlobalPool>(resource_address()).metadata_lp.borrow_mut(pair_asset);
        fungible_asset::deposit(token_pair_metadata.balance_y, amount);
    }

    // Calculate the amount of LP tokens to be minted for the sender and the fee recipient (fee_to)
    fun mint(
        pair_asset: PairAsset,
    ): (u64, u64) acquires GlobalPool, SwapInfo, Management {
        let pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(resource_address());

        let token_pair_metadata: &mut TokenPairMetadata = pool.metadata_lp.borrow_mut(pair_asset);
        let token_pair_reserve: &mut TokenPairReserve = pool.reserve_lp.borrow_mut(pair_asset);

        let (balance_x, balance_y): (
            Object<FungibleStore>, Object<FungibleStore>
        ) = (token_pair_metadata.balance_x, token_pair_metadata.balance_y);
        let (reserve_x, reserve_y): (u64, u64) = (token_pair_reserve.reserve_x, token_pair_reserve.reserve_y);

        // It needs to be recalculated due to the updated balance
        // Since the reserver isn't updated together with the balance, calculations here would be inaccurate
        let amount_x: u128 = (fungible_asset::balance(balance_x) as u128) - (reserve_x as u128);
        let amount_y: u128 = (fungible_asset::balance(balance_y) as u128) - (reserve_y as u128);

        let fee_amount: u64 = calculate_and_mint_fee(pair_asset, reserve_x, reserve_y, token_pair_metadata);

        let address_lp: address = get_address_pair_asset(pair_asset);
        let total_supply: u128 = get_total_supply(address_lp);
        let liquidity: u128 = if (total_supply == 0u128) {
            let lp_total_amount: u128 = math128::sqrt(amount_x * amount_y);
            assert!(lp_total_amount > MINIMUM_LIQUIDITY, ERROR_SUFFICIENT_LIQUIDITY_MINTED);

            let amount_token_lp: u128 = lp_total_amount - MINIMUM_LIQUIDITY;
            // When liquidity is first added, the pool is automatically minted with MINIMUM_LIQUIDITY
            transfer_lp_to(
                pair_asset,
                swap_utils::get_address_pair_asset(pair_asset),
                (MINIMUM_LIQUIDITY as u64)
            );
            amount_token_lp
        } else {
            let liquidity: u128 = math128::min(
                amount_x * total_supply / (reserve_x as u128),
                amount_y * total_supply / (reserve_y as u128)
            );
            assert!(liquidity > 0, ERROR_SUFFICIENT_LIQUIDITY_MINTED);
            liquidity
        };

        update(
            fungible_asset::balance(balance_x),
            fungible_asset::balance(balance_y),
            token_pair_reserve
        );
        token_pair_metadata.k_last = (token_pair_reserve.reserve_x as u128) * (token_pair_reserve.reserve_y as u128);
        ((liquidity as u64), fee_amount)
    }

    // fun burn(pair_asset: PairAsset, liquidity: u64): (FungibleAsset, FungibleAsset, u64) acquires GlobalPool, SwapInfo, Management {
    //     let pool: &mut GlobalPool = borrow_global_mut<GlobalPool>(resource_address());
    //
    //     let token_pair_metadata: &mut TokenPairMetadata = pool.metadata_lp.borrow_mut(pair_asset);
    //     let token_pair_reserve: &mut TokenPairReserve = pool.reserve_lp.borrow_mut(pair_asset);
    //
    //     let (balance_x, balance_y): (
    //         Object<FungibleStore>, Object<FungibleStore>
    //     ) = (token_pair_metadata.balance_x, token_pair_metadata.balance_y);
    //     let amount_balance_x: u64 = fungible_asset::balance(balance_x);
    //     let amount_balance_y: u64 = fungible_asset::balance(balance_y);
    //
    //     let (reserve_x, reserve_y): (u64, u64) = (token_pair_reserve.reserve_x, token_pair_reserve.reserve_y);
    //
    //     let fee_amount: u64 = calculate_and_mint_fee(pair_asset, reserve_x, reserve_y, token_pair_metadata);
    //     // It needs to be recalculated due to the updated balance
    //     // Since the reserver isn't updated together with the balance, calculations here would be inaccurate
    //     let addr_fa: address = swap_utils::get_address_pair_asset(pair_asset);
    //     let total_lp_supply: u128 = get_total_supply(addr_fa);
    //     let amount_x: u128 = ((amount_balance_x as u128) * (liquidity as u128) / (total_lp_supply));
    //     let amount_y: u128 = ((amount_balance_y as u128) * (liquidity as u128) / (total_lp_supply));
    //     assert!(amount_x > 0 && amount_y > 0, ERROR_SUFFICIENT_LIQUIDITY_BURNED);
    //
    //
    //
    //     let address_lp: address = get_address_pair_asset(pair_asset);
    //     let total_supply: u128 = get_total_supply(address_lp);
    //     let liquidity: u128 = if (total_supply == 0u128) {
    //         let lp_total_amount: u128 = math128::sqrt(amount_x * amount_y);
    //         assert!(lp_total_amount > MINIMUM_LIQUIDITY, ERROR_SUFFICIENT_LIQUIDITY_MINTED);
    //
    //         let amount_token_lp: u128 = lp_total_amount - MINIMUM_LIQUIDITY;
    //         // When liquidity is first added, the pool is automatically minted with MINIMUM_LIQUIDITY
    //         transfer_lp_to(
    //             pair_asset,
    //             swap_utils::get_address_pair_asset(pair_asset),
    //             (MINIMUM_LIQUIDITY as u64)
    //         );
    //         amount_token_lp
    //     } else {
    //         let liquidity: u128 = math128::min(
    //             amount_x * total_supply / (reserve_x as u128),
    //             amount_y * total_supply / (reserve_y as u128)
    //         );
    //         assert!(liquidity > 0, ERROR_SUFFICIENT_LIQUIDITY_MINTED);
    //         liquidity
    //     };
    //
    //     update(
    //         fungible_asset::balance(balance_x),
    //         fungible_asset::balance(balance_y),
    //         token_pair_reserve
    //     );
    //
    //     token_pair_metadata.k_last = (token_pair_reserve.reserve_x as u128) * (token_pair_reserve.reserve_y as u128);
    //     ((liquidity as u64), fee_amount)
    // }

    fun calculate_and_mint_fee(
        pair_asset: PairAsset,
        reserve_x: u64,
        reserve_y: u64,
        token_pair_metadata: &mut TokenPairMetadata
    ): u64 acquires Management, SwapInfo {
        let fee: u64 = 0u64;
        if (token_pair_metadata.k_last > 0) {
            let k_last: u128 = math128::sqrt((reserve_x as u128) * (reserve_y as u128));
            let k_new: u128 = math128::sqrt(token_pair_metadata.k_last);
            if (k_new > k_last) {
                let numerator: u128 = get_total_supply(
                    get_address_pair_asset(pair_asset)
                ) * (k_new - k_last) * 8u128;
                let deiminator: u128 = k_last * 8u128 + k_new * 17u128;
                let liquidity: u128 = numerator / deiminator;
                fee = (liquidity as u64);
                // mint fee if
                if (fee > 0) {
                    let fee_amount: Object<FungibleStore> = token_pair_metadata.fee_amount;
                    transfer_lp_to_obj(
                        pair_asset,
                        fee_amount,
                        fee
                    );
                }
            }
        };
        fee
    }

    fun update(
        balance_x: u64,
        balance_y: u64,
        token_pair_reserve: &mut TokenPairReserve
    ) {
        token_pair_reserve.reserve_x = balance_x;
        token_pair_reserve.reserve_y = balance_y;
        token_pair_reserve.block_timestamp_last = timestamp::now_seconds();
    }

    public fun mint_lp_to(
        pair_asset: PairAsset,
        addr_to: address,
        amount: u64
    ) acquires Management, SwapInfo {
        let pa_addr: address = swap_utils::get_address_pair_asset(pair_asset);
        let symbol: vector<u8> = *swap_utils::get_symbol(pa_addr).bytes();

        let management: &Management = borrow_global<Management>(creator_address(symbol));
        let mint_ref: &MintRef = &management.mint_ref;
        let store_to: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
            addr_to,
            swap_utils::get_object_metadata(pa_addr)
        );
        fungible_asset::mint_to(mint_ref, store_to, amount);
    }

    // mint and deposit
    public fun transfer_lp_to(
        pair_asset: PairAsset,
        addr_to: address,
        amount: u64
    ) acquires Management, SwapInfo {
        let pa_addr: address = swap_utils::get_address_pair_asset(pair_asset);
        let symbol: vector<u8> = *swap_utils::get_symbol(pa_addr).bytes();

        let addr_creator: address = swap_utils::get_address_pair_asset(pair_asset);
        let pa_metadata: Object<Metadata> = swap_utils::get_object_metadata(addr_creator);

        let management: &Management = borrow_global<Management>(creator_address(symbol));
        let transfer_ref: &TransferRef = &management.transfer_ref;
        let mint_ref: &MintRef = &management.mint_ref;

        let store_to: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
            addr_creator,
            pa_metadata
        );

        fungible_asset::mint_to(mint_ref, store_to, amount);

        primary_fungible_store::transfer_with_ref(
            transfer_ref,
            addr_creator,
            addr_to,
            amount
        );
    }


    public fun transfer_lp_to_obj(
        pair_asset: PairAsset,
        store_to: Object<FungibleStore>,
        amount: u64
    ) acquires Management, SwapInfo {
        let pa_addr: address = swap_utils::get_address_pair_asset(pair_asset);
        let symbol: vector<u8> = *swap_utils::get_symbol(pa_addr).bytes();
        print(&get_total_supply(pa_addr));
        let addr_creator: address = swap_utils::get_address_pair_asset(pair_asset);
        let pa_metadata: Object<Metadata> = swap_utils::get_object_metadata(addr_creator);
        let store_from: Object<FungibleStore> = primary_fungible_store::primary_store(
            addr_creator,
            pa_metadata
        );

        let management: &Management = borrow_global<Management>(creator_address(symbol));
        let transfer_ref: &TransferRef = &management.transfer_ref;
        let mint_ref: &MintRef = &management.mint_ref;

        fungible_asset::mint_to(mint_ref, store_from, amount);

        fungible_asset::transfer_with_ref(
            transfer_ref,
            store_from,
            store_to,
            amount
        );
    }


    #[test_only(sender = @swap)]
    public fun init_for_test_pool(admin: &signer) {
        init_module(admin);
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
}