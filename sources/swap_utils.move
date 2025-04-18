module swap::swap_utils {
    /***********/
    /* library */
    /***********/
    use std::option::Option;
    use std::signer;
    use std::string::{String, utf8};
    use aptos_std::comparator;
    use aptos_std::comparator::Result;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{Metadata, MintRef, BurnRef, FungibleStore, TransferRef};
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};
    use aptos_framework::primary_fungible_store;

    /***********************/
    /* constant parameters */
    /***********************/
    const ADDRESS_RESOURCE: address = @swap;
    const RESOURCE_SEED: vector<u8> = b"RESOURCE";
    const SYMBOL_RESOURCE: vector<u8> = b"FA LP";
    const SYMBOL_USERS: vector<u8> = b"Users Management";

    const ERROR_NOT_ADMIN_RESOURCE: u64 = 1;
    const ERROR_NOT_CREATOR_FA: u64 = 2;
    const ERROR_INVALID_AMOUNT: u64 = 3;
    const ERROR_SAME_FA: u64 = 4;

    /**********/
    /* struct */
    /**********/
    struct AssetRegistry has store {
        fa_map: SmartTable<vector<u8>, address>,
        lp_map: SmartTable<vector<u8>, address>,
    }

    struct PairAsset has copy, drop, store {
        token_x: address,
        token_y: address,
    }

    struct PoolRegistry has store {
        pool_map: SmartTable<PairAsset, address>,
    }

    struct GlobalState has key {
        assets: AssetRegistry,
        pools: PoolRegistry,
    }

    // A struct to manage minting and burning activities
    struct Management has key {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    /************/
    /* function */
    /************/

    fun init_module(admin: &signer) {
        let asset_registry: AssetRegistry = AssetRegistry {
            fa_map: smart_table::new(),
            lp_map: smart_table::new()
        };

        let pool_registry: PoolRegistry = PoolRegistry {
            pool_map: smart_table::new()
        };

        let constructor_ref: &ConstructorRef = &object::create_named_object(admin, SYMBOL_RESOURCE);
        let resource_signer: signer = object::generate_signer(constructor_ref);

        move_to(
            &resource_signer,
            GlobalState {
                assets: asset_registry,
                pools: pool_registry
            }
        );
    }

    public fun init_FA(
        creator: &signer,
        max_supply: Option<u128>,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        icon_uri: vector<u8>,
        project_uri: vector<u8>,
    ) acquires GlobalState {
        let constructor_ref: &ConstructorRef = &object::create_named_object(creator, symbol);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            max_supply,
            utf8(name),
            utf8(symbol),
            decimals,
            utf8(icon_uri),
            utf8(project_uri),
        );

        let addr: address = object::create_object_address(&signer::address_of(creator), symbol);
        add_fa_map(symbol, addr);

        let manage_signer: signer = object::generate_signer(constructor_ref);
        move_to(
            &manage_signer,
            Management {
                mint_ref: fungible_asset::generate_mint_ref(constructor_ref),
                burn_ref: fungible_asset::generate_burn_ref(constructor_ref),
                transfer_ref: fungible_asset::generate_transfer_ref(constructor_ref)
            }
        );
    }

    public fun init_LP(
        constructor_ref: &ConstructorRef,
        max_supply: Option<u128>,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        icon_uri: vector<u8>,
        project_uri: vector<u8>,
    ) {
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            max_supply,
            utf8(name),
            utf8(symbol),
            decimals,
            utf8(icon_uri),
            utf8(project_uri),
        );
    }

    /* get function */
    public fun get_addr_resource(): address {
        object::create_object_address(&ADDRESS_RESOURCE, SYMBOL_RESOURCE)
    }

    public fun get_addr_fa(symbol_fa: vector<u8>): address acquires GlobalState {
        *borrow_global<GlobalState>(get_addr_resource()).assets.fa_map.borrow(symbol_fa)
    }

    public fun get_obj_metadata_fa(addr_fa: address): Object<Metadata> {
        object::address_to_object(addr_fa)
    }

    public fun get_metadata_fa(addr_fa: address): Metadata {
        let obj_metadata: Object<Metadata> = get_obj_metadata_fa(addr_fa);
        fungible_asset::metadata(obj_metadata)
    }

    public fun get_symbol_fa(addr_fa: address): String {
        let obj_metadata: Object<Metadata> = get_obj_metadata_fa(addr_fa);
        fungible_asset::symbol(obj_metadata)
    }

    public fun get_name_fa(addr_fa: address): String {
        let obj_metadata: Object<Metadata> = get_obj_metadata_fa(addr_fa);
        fungible_asset::name(obj_metadata)
    }

    public fun get_addr_pair_asset(pa: PairAsset): address acquires GlobalState {
        *borrow_global<GlobalState>(get_addr_resource()).pools.pool_map.borrow(pa)
    }

    public fun get_addr_fa_x_y(pa: PairAsset): (address, address){
        (pa.token_x, pa.token_y)
    }

    public fun make_pair_asset(addr1: address, addr2: address): PairAsset {
        PairAsset {
            token_x: addr1,
            token_y: addr2
        }
    }

    /* entry function */
    public fun add_pool_map(pa: PairAsset, addr: address) acquires GlobalState {
        let global_state: &mut GlobalState = borrow_global_mut<GlobalState>(get_addr_resource());
        global_state.pools.pool_map.add(pa, addr);
    }

    public fun add_fa_map(symbol: vector<u8>, addr: address) acquires GlobalState {
        let global_state: &mut GlobalState = borrow_global_mut<GlobalState>(get_addr_resource());
        global_state.assets.fa_map.add(symbol, addr);
    }

    public fun add_lp_map(symbol: vector<u8>, addr: address) acquires GlobalState {
        let global_state: &mut GlobalState = borrow_global_mut<GlobalState>(get_addr_resource());
        global_state.assets.lp_map.add(symbol, addr);
    }

    /* check function */
    public fun compare_symbol_fa(addr_x: address, addr_y: address): bool {
        let symbol_x: vector<u8> = *get_symbol_fa(addr_x).bytes();
        let symbol_y: vector<u8> = *get_symbol_fa(addr_y).bytes();
        let result: Result = comparator::compare_u8_vector(symbol_x, symbol_y);
        assert!(!result.is_equal(), ERROR_SAME_FA);
        result.is_smaller_than()
    }

    public fun compare_pair_asset(pa1: PairAsset, pa2: PairAsset): bool {
        (pa1.token_x == pa2.token_x && pa1.token_y == pa2.token_y) || (pa1.token_y == pa2.token_x && pa1.token_x == pa2.token_y)
    }

    public fun exist_data(admin: &signer): bool {
        let addr_admin: address = signer::address_of(admin);
        exists<GlobalState>(addr_admin)
    }

    public fun exist_fa(symbol_fa: vector<u8>): bool acquires GlobalState {
        let fa_map: &SmartTable<vector<u8>, address> = &borrow_global<GlobalState>(get_addr_resource()).assets.fa_map;
        fa_map.contains(symbol_fa)
    }

    public fun exists_pair_asset(pa: PairAsset): bool acquires GlobalState {
        let pool_map: &SmartTable<PairAsset, address> = &borrow_global<GlobalState>(get_addr_resource()).pools.pool_map;
        pool_map.contains(pa)
    }

    public entry fun mint_fa(
        minter: &signer,
        addr_fa: address,
        addr_to: address,
        amount: u64
    ) acquires Management {
        assert!(amount > 0, ERROR_INVALID_AMOUNT);
        let symbol_fa: vector<u8> = *get_symbol_fa(addr_fa).bytes();
        let addr: address = object::create_object_address(&signer::address_of(minter), symbol_fa);
        assert!(addr == addr_fa, ERROR_NOT_CREATOR_FA);
        let fa_metadata: Object<Metadata> = get_obj_metadata_fa(addr_fa);

        let mint_ref: &MintRef = &borrow_global<Management>(addr_fa).mint_ref;
        let store: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
            addr_to,
            fa_metadata,
        );

        fungible_asset::mint_to(
            mint_ref,
            store,
            amount
        );
    }

    public fun transfer_asset_from_to(
        addr_from: address,
        addr_to: address,
        addr_fa: address,
        amount: u64
    ) acquires Management {
        let metadata_fa: Object<Metadata> = get_obj_metadata_fa(addr_fa);
        let store_from: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
            addr_from,
            metadata_fa
        );
        let store_to: Object<FungibleStore> = primary_fungible_store::ensure_primary_store_exists(
            addr_to,
            metadata_fa
        );
        let management: &Management = borrow_global<Management>(addr_fa);
        let transfer_ref: &TransferRef = &management.transfer_ref;

        fungible_asset::transfer_with_ref(
            transfer_ref,
            store_from,
            store_to,
            amount
        );
    }

    #[test_only]
    public fun init_for_test_untils(admin: &signer) {
        init_module(admin);
    }
}