#[test_only]
module swap::swap_utils_test {
    use std::option;
    use std::signer;
    use swap::swap_pool;
    use swap::swap_utils;

    const ERROR_POOL_ADDRESS: u64 = 1;


    #[test(admin = @swap, user = @user)]
    fun test_init(admin: &signer, user: &signer) {
        swap_utils::init_for_test_untils(admin);
        swap_pool::init_for_test_pool(admin);
        swap_utils::init_FA(
            user,
            option::none(),
            b"USDT",
            b"USD",
            8,
            b"",
            b""
        );

        swap_utils::init_FA(
            user,
            option::none(),
            b"Binance",
            b"BNB",
            8,
            b"",
            b""
        );

        let addr_usd: address = swap_utils::get_addr_fa(b"USD");
        let addr_bnb: address = swap_utils::get_addr_fa(b"BNB");

        swap_pool::create_pair(
            user,
            addr_bnb,
            addr_usd
        );
    }

    #[test(creator = @swap, user = @user, user1 = @0xcafe)]
    fun test_mint(creator: &signer, user: &signer, user1: &signer) {
        swap_utils::init_for_test_untils(creator);
        swap_utils::init_FA(
            user,
            option::none(),
            b"Binance",
            b"BNB",
            8,
            b"",
            b""
        );
        let addr_bnb: address = swap_utils::get_addr_fa(b"BNB");
        // print(&addr_bnb);
        let addr_receive: address = signer::address_of(user1);
        swap_utils::mint_fa(user, addr_bnb, addr_receive, 10);
        assert!(swap_pool::get_balance(addr_bnb, addr_receive) == 10, 1);
        assert!(swap_pool::get_total_supply(addr_bnb) == 10, 1);
        swap_utils::mint_fa(user, addr_bnb, signer::address_of(user), 111);
        assert!(swap_pool::get_total_supply(addr_bnb) == 121, 1);
    }
}
