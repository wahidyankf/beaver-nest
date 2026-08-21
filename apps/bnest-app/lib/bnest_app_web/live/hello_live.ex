defmodule BnestAppWeb.HelloLive do
  use BnestAppWeb, :live_view

  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-3xl px-6 py-24">
      <h1 class="text-4xl font-bold">Hello, WW!</h1>
      <p class="mt-4 text-lg">Welcome to Beaver Nest.</p>
    </main>
    """
  end
end
