defmodule BnestApp.Identity.Domain.Credentials do
  @moduledoc """
  The username and password rules. A username is 1–32 ASCII letters, digits, dots, dashes
  or underscores, compared case-insensitively. A password is any valid Unicode string with
  a letter, a digit and a punctuation mark; it has no length rule and is never trimmed.
  """

  @username_pattern ~r/\A[a-z0-9](?:[a-z0-9._-]{0,30}[a-z0-9])?\z/u

  @doc "The trimmed display form and the ASCII-lowercased form of a valid username."
  @spec normalize_username(term()) ::
          {:ok, {String.t(), String.t()}} | {:error, :invalid_username}
  def normalize_username(username) when is_binary(username) do
    display = String.trim(username)
    normalized = ascii_lower(display)

    if String.valid?(display) and String.length(display) in 1..32 and
         Regex.match?(@username_pattern, normalized) do
      {:ok, {display, normalized}}
    else
      {:error, :invalid_username}
    end
  end

  def normalize_username(_username), do: {:error, :invalid_username}

  @spec valid_password?(term()) :: boolean()
  def valid_password?(password) when is_binary(password) do
    String.valid?(password) and
      password != "" and
      String.match?(password, ~r/\p{L}/u) and
      String.match?(password, ~r/\p{Nd}/u) and
      String.match?(password, ~r/[[:punct:]]/u)
  end

  def valid_password?(_password), do: false

  defp ascii_lower(value) do
    value
    |> :binary.bin_to_list()
    |> Enum.map(fn char -> if char in ?A..?Z, do: char + 32, else: char end)
    |> :binary.list_to_bin()
  end
end
