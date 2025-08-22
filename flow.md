company creation -> RyzerRegistryTest::test_RegisterCompany

asset creation -> RyzerRealEstateToken. ---> RyzerRealEstateTokenFactoryTest::test_DeployProject_USDC, test_DeployProject_USDT

place order ->//@note --have to write test case //RyzerOrderManagerTest

complete order (finalizeOrder)->//@note --have to write test case //RyzerOrderManagerTest

token transfer -- escrow ->invester

dividend distribution. (RyzerEscrow::distributeDividend) --logic ->
when company creates the asset, the value of that asset is 10 lakhs and asset tokenized into 10,000 tokens, each token value 10,00,000/10,000. when investor came and purchase 100 tokens (real estate token(asset tokens)), and when he pays 100 \* 100 = 10,000 rupees, he will get 100 tokens (asset tokens), ownernship of investor of that real estate asset is (10,00,000/10,000) \* (1/100) is 1%. The rental yield of that asset is 30,000 per month. Dividend of investor is (30,000)\* (1/100) is 300 INR.

https://github.com/TokenySolutions/T-REX/blob/main/contracts/compliance/modular/ModularCompliance.sol

https://github.com/TokenySolutions/T-REX/blob/main/contracts/registry/implementation/IdentityRegistry.sol

deployment script flow ->

RyzerCompany. (w/o proxy)
RyzerRealEstateToken (w/o proxy) (projectTokenImpl)

RyzerDAO (w/o proxy)
RyzerEscrow (w/o proxy)
RyzerOrderManager (w/o proxy)

RyzerCompanyFactory (w proxy)
RyzerRealEstateFactory (w proxy)
RyzerRegistry (w proxy)

Normal Contracts - usdc mock, usdt mock

initilization script -
company factory , realstate factory, ryzer registory (initialize)
