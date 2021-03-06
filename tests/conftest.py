import pytest
from brownie import config
from brownie import Contract

@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)


@pytest.fixture
def user(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]

@pytest.fixture
def gov(accounts):
    yield accounts[6]

@pytest.fixture
def yfi_whale(accounts, yfi):
    yfi.mint(accounts[7], "100 ether")
    yield accounts[7]

@pytest.fixture
def token():
    token_address = "0x6b175474e89094c44da98b954eedeac495271d0f"  # DAI
    yield Contract(token_address)

@pytest.fixture
def yfi():
    yfi_address = "0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e"
    yield Contract(yfi_address)

@pytest.fixture
def daddy(accounts):
    yield accounts.at("0x026D4b8d693f6C446782c2C61ee357Ec561DFB61", force=True)

@pytest.fixture
def amount(accounts, token, user):
    amount = 10_000 * 10 ** token.decimals()
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    reserve = accounts.at("0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643", force=True)
    token.transfer(user, amount, {"from": reserve})
    yield amount


@pytest.fixture
def weth():
    token_address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    yield Contract(token_address)


@pytest.fixture
def weth_amout(user, weth):
    weth_amout = 10 ** weth.decimals()
    user.transfer(weth, weth_amout)
    yield weth_amout

@pytest.fixture
def masterchef(MasterChef, web3, gov, yfi, token, daddy):
    masterchef = gov.deploy(MasterChef, yfi, gov, 10**9, web3.eth.block_number, web3.eth.block_number + 1000000)
    yfi.addMinter(masterchef, {"from": daddy})
    masterchef.add(1000, token, 1)

    yield masterchef

@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, management)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture
def strategy(strategist, keeper, vault, Strategy, gov, masterchef, yfi):
    strategy = strategist.deploy(Strategy, vault, masterchef, 0)
    strategy.setKeeper(keeper, {"from": gov})
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5
