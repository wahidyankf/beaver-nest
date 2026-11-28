%{
  configs: [
    %{
      name: "default",
      requires: [".credo/checks/unit_hermeticity.ex"],
      checks: %{
        extra: [
          {BnestApp.Credo.Checks.UnitHermeticity,
           [
             files: %{included: ["test/unit/**/*.{ex,exs}"]}
           ]}
        ]
      }
    }
  ]
}
