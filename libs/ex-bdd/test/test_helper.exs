# Start ExUnit
ExUnit.start()

# Compile the library's deliberately invalid/ambiguous runtime fixtures through
# the internal compiler path. Consumer-facing ExBdd.compile_features!/1 always
# performs strict verification first.
ExBdd.Discovery.discover()
|> ExBdd.Compiler.compile_discovery!()
