# Membrane ERTMP Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_ertmp_plugin.svg)](https://hex.pm/packages/membrane_ertmp_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ertmp_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_ertmp_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_ertmp_plugin)

Membrane plugin for Enhanced RTMP (ERTMP) output, built on top of the RTMP package of [software-mansion/smelter](https://github.com/software-mansion/smelter).

It's a part of the [Membrane Framework](https://membrane.stream).

## Installation

The package can be installed by adding `membrane_ertmp_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_ertmp_plugin, "~> 0.1.0"}
  ]
end
```

## Usage

See [`examples/sink_example.exs`](examples/sink_example.exs) for a complete pipeline that streams an MP4 file to an RTMP server using `Membrane.ERTMP.Sink`. Run it with:

```sh
mix run examples/sink_example.exs [rtmp://host:port/app/key]
```

## Copyright and License

Copyright 2026, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_ertmp_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_ertmp_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
