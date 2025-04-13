#[test_only]
module swap::swap_pool_test {
    use std::option;
    use std::signer;
    use aptos_std::debug::print;
    use swap::swap_resource;
    use swap::swap_resource::{PairAsset, get_symbol};
    use swap::swap_pool;
    use aptos_framework::coin;
    use swap::swap_pool::{Management, exists_management};

    const ERROR_POOL_ADDRESS: u64 = 1;
    const ERROR_CREATE_PAIR: u64 = 2;

    #[test(creator = @swap)]
    fun test_init_module(creator: &signer) {
        swap_pool::init_for_test_pool(creator);
        assert!(swap_pool::exists_swap_info(), ERROR_POOL_ADDRESS);
        assert!(swap_pool::exists_global_pool(), ERROR_POOL_ADDRESS);

    }

    #[test(creator = @swap, user = @user)]
    fun test_create_pair(creator: &signer, user: &signer) {
        swap_resource::init_for_test_resource(creator);
        swap_pool::init_for_test_pool(creator);
        swap_resource::init_FA(
            user,
            option::none(),
            b"USDT",
            b"USD",
            8,
            b"",
            b""
        );

        swap_resource::init_FA(
            user,
            option::none(),
            b"Binance",
            b"BNB",
            8,
            b"",
            b""
        );
        let addr_usd: address = swap_resource::get_address_FA(b"USD");
        let addr_bnb: address = swap_resource::get_address_FA(b"BNB");
        swap_pool::create_pair(
            user,
            addr_bnb,
            addr_usd
        );
        let pa: PairAsset = swap_resource::make_pair_asset(addr_bnb, addr_usd);
        assert!(swap_pool::is_contain(pa), ERROR_CREATE_PAIR);
        assert!(
            swap_pool::exists_management(
                swap_pool::resource_address(),
                pa
            ),
            0
        );
    }

    #[test(creator = @swap, user = @user)]
    #[expected_failure(abort_code = swap_pool::ERROR_SAME_FUNGIBLE_ASSET, location = swap_pool)]
    fun test_create_pair_same_fa(creator: &signer, user: &signer) {
        swap_pool::init_for_test_pool(creator);
        swap_resource::init_for_test_resource(creator);
        swap_resource::init_FA(
            user,
            option::none(),
            b"Binance",
            b"BNB",
            8,
            b"",
            b""
        );
        let addr_bnb: address = swap_resource::get_address_FA(b"BNB");
        swap_pool::create_pair(
            user,
            addr_bnb,
            addr_bnb
        );
    }
}
