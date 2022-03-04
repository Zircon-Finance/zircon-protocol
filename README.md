![](https://img.shields.io/badge/Zircon-blueviolet)

# Zircon Protocol

[![code style: prettier](https://img.shields.io/badge/code_style-prettier-ff69b4.svg?style=flat-square)](https://github.com/prettier/prettier)
[![Actions Status](https://github.com/Uniswap/uniswap-sdk/workflows/CI/badge.svg)](https://github.com/Uniswap/uniswap-sdk)
[![npm version](https://img.shields.io/npm/v/@uniswap/sdk/latest.svg)](https://www.npmjs.com/package/@uniswap/sdk/v/latest)
[![npm bundle size (scoped version)](https://img.shields.io/bundlephobia/minzip/@uniswap/sdk/latest.svg)](https://bundlephobia.com/result?p=@uniswap/sdk@latest)

In-depth documentation on this SDK is available at [uniswap.org](https://uniswap.org/docs/v2/SDK/getting-started/), and the documentation on pylon at [zircon.finance](https://docs.zircon.finance)


## Links
  - [Website](https://www.zircon.finance/)
  - [Beta](https://beta.zircon.finance/)
  - [Docs](https://docs.zircon.finance/)
 
  Socials:
  - [Discord](https://discord.gg/wbqNAqvvTg)
  - [Twitter](https://twitter.com/Zircon_Finance)
  - [Email](mailto:hello@zircon.finance)
  - [Reddit](https://www.reddit.com/r/zirconfinance)

## Pylon Enhancements

The protocol includes the contracts handling pylon new features.

Our architecture works on top of Uniswap v2, enabling the creation of two pylons per pair, that can handle the single-sided liquidity. Our Pylon is not an ERC-20 token as Uniswap Pair instead we created another contract Zircon Pool Token that is the ERC-20 Token for the Float and Anchor Shares.

Zircon Pylon keeps a percentage of reserves and the Pool Token Shares, to handle the principal transactions.
Our Pylon Router, handles all the communication, between the user and the Pylon. 

## Running tests

To run the tests, follow these steps. You must have at least node v10 and [yarn](https://yarnpkg.com/) installed.

First clone the repository:

```sh
git clone git@github.com:Zircon-Finance/zircon-protocol.git
```

Move into the zircon-protocol working directory

```sh
cd zircon-sdk/
```

Install dependencies

```sh
yarn compile
```

Run tests

```sh
yarn test
```

