### 编译circuits
```
yarn build:circuit
```

编辑`/circuits/withdraw.circom`的最后一行：

```
component main = Withdraw(14);
```

可以调整`Merkle树`的层数。层数越高，GAS费越高

编译完成后，在`/build/`目录下，会产生`circuits`目录，将此目录完整的复制到`shaker`前端的`/public`目录下。

另外，将`circuits`目录下的`withdraw.json`文件复制到前端`/src/circuits/`目录下。

### 部署合约
合约源文件：`/contracts`目录下。

部署时，用的账户是.env文件中的私钥对应账户。

部署合约前，需要设置`.env`文件中的`ERC20_TOKEN`，即`USDT`合约地址。并确保`MERKLE_TREE_HEIGHT`默克尔树的高度和编译`circuit`时的一致。

根据不同的以太坊网络，采用不同的合约部署命令：

```
yarn migrate:dev //本地开发网络
yarn migrate:kovan
yarn migrate:rinkeby
yarn migrate:mainnet
```
如果全新部署，在上面命令行后加`--reset`。如果部署过程中出现错误，则把`--reset`去掉，再次执行。

部署完成后，将`ERC20Shaker`合约地址复制到`shaker`前端`/client/config.js` 中的`ERC20ShakerAddress` 中；将`ETHShaker`合约地址复制到`config.js`的`ETHShakerAddress`中。

另外，将合约ABI文件`ERC20Shaker.json`和`ETHShaker.json`复制到`shaker`前端的`/src/contracts`目录中。

还要将合约ABI文件中内容，复制到`Relayer`的`mixerABI.json`中。

### 测试合约命令
#### Deposit
```
./cli.js test
```

#### Withdraw
```
./cli.js withdraw shaker-usdt-5-2000-0x8338941878995cc0c5df9aaa1e4d5307c2d41a678aade05dce3ad8b3858dacea19e4ecbb3fb24b9ae3bc62ad831ac034350108321fe5c2e809471c8803d9 0xC804C9bFAe7Da9C4C409120773d0B4107cfACBBF 1 --rpc https://kovan.infura.io/v3/0279e3bdf3ee49d0b547c643c2ef78ef
```

#### 查询存单
```
./cli.js compliance shaker-usdt-5-2000-0x4aa1a3848578f716c6dce7e358e6bcdfbcb8e3e3ec1944ba8d45083d77e7f014acb4618ab51e7cbf19bec092abe87153e45209a2a01e76e63af797adfd70
```

