# These generated feature tests intentionally cross the real filesystem boundary.
# Consumer-facing ExBdd.compile_features!/1 still performs strict verification first.
ExBdd.Discovery.discover()
|> ExBdd.Compiler.compile_discovery!()
