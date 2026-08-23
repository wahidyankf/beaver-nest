defmodule ShoppingSteps do
  @moduledoc """
  Shopping cart steps for ExBdd tests.
  """
  use ExBdd.StepDefinition
  import ExUnit.Assertions

  step "I have {int} items in my cart", %{args: [item_count]} = context do
    Map.put(context, :cart_items, item_count)
  end

  step "I should have {int} items total", %{args: [expected_count]} = context do
    assert context.cart_items == expected_count
    context
  end
end
