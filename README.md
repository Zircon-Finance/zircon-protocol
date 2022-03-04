![](https://img.shields.io/badge/Zircon-blueviolet)

# Zircon Protocol

[![code style: prettier](https://img.shields.io/badge/code_style-prettier-ff69b4.svg?style=flat-square)](https://github.com/prettier/prettier)
[![Actions Status](https://github.com/Uniswap/uniswap-sdk/workflows/CI/badge.svg)](https://github.com/Uniswap/uniswap-sdk)
[![npm version](https://img.shields.io/npm/v/@uniswap/sdk/latest.svg)](https://www.npmjs.com/package/@uniswap/sdk/v/latest)
[![npm bundle size (scoped version)](https://img.shields.io/bundlephobia/minzip/@uniswap/sdk/latest.svg)](https://bundlephobia.com/result?p=@uniswap/sdk@latest)

In-depth documentation on this SDK is available at [uniswap.org](https://uniswap.org/docs/v2/SDK/getting-started/), while basic documentation for Pylon at [zircon.finance](https://docs.zircon.finance)


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

The protocol includes the contracts handling Pylon and its new single-sided liquidity features.

Our architecture works on top of Uniswap v2, enabling the creation of two Pylons per pair, which handle the single-sided liquidity provision. Each Pylon holds both UniV2 LP tokens of its associated pool and a percentage of reserves of both tokens in the pair. Pylon extends on the basic Uniswap Pair ERC-20 token with the Zircon Pool Token, which is an ERC-20 representation for the Float and Anchor Shares.

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

