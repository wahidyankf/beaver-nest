import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/bnest_app start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
env = BnestApp.RuntimeSettings.system_env()

if BnestApp.RuntimeSettings.server_enabled?(env) do
  config :bnest_app, BnestAppWeb.Endpoint, server: true
end

config :bnest_app, BnestAppWeb.Endpoint, http: [port: BnestApp.RuntimeSettings.http_port(env)]

if runtime_root = BnestApp.RuntimeSettings.runtime_root(env) do
  config :bnest_app, :runtime_root, runtime_root
end

if codex_working_directory = BnestApp.RuntimeSettings.codex_working_directory(env) do
  config :bnest_app, :codex, working_directory: codex_working_directory
end

if codex_home = BnestApp.RuntimeSettings.codex_home(env) do
  config :bnest_app, :codex, codex_home: codex_home
end

case BnestApp.RuntimeSettings.boolean_setting!(env, "BNEST_IDENTITY_CUTOVER", :unset) do
  :unset -> :ok
  true -> config :bnest_app, :identity_cutover_enabled, true
  false -> config :bnest_app, :identity_cutover_enabled, false
end

# Compatibility release ships this `false` (dormant shell, no navigation
# entry, route itself returns 404); the later experience release flips it
# `true` from the same reviewed revision -- no redeploy, no schema change
# (tech-doc 007's Runtime Configuration contract).
case BnestApp.RuntimeSettings.boolean_setting!(env, "BNEST_FAMILY_CHAT_ENABLED", :unset) do
  :unset -> :ok
  true -> config :bnest_app, :family_chat_enabled, true
  false -> config :bnest_app, :family_chat_enabled, false
end

# Gates the requested GraphQL fields, the action menu, and the composer's
# reply strip together, so the browser never asks for a field it will not
# render. Independent of the flag above: the compatibility release ships this
# `false` with the room itself already live, and the experience release flips
# it `true` from the same reviewed revision.
case System.get_env("BNEST_FAMILY_CHAT_REPLY_ENABLED") do
  nil -> :ok
  "true" -> config :bnest_app, :family_chat_reply_enabled, true
  "false" -> config :bnest_app, :family_chat_reply_enabled, false
  _invalid -> raise "BNEST_FAMILY_CHAT_REPLY_ENABLED must be true or false"
end

case BnestApp.RuntimeSettings.boolean_setting!(env, "BNEST_COOKIE_SECURE", :unset) do
  :unset -> :ok
  true -> config :bnest_app, :session_cookie, secure: true
  false -> config :bnest_app, :session_cookie, secure: false
end

case System.get_env("BNEST_BACKUP_TIMEOUT_MS") do
  nil ->
    :ok

  raw ->
    case Integer.parse(raw) do
      {ms, ""} when ms in 60_000..7_200_000 -> config :bnest_app, :backup_timeout_ms, ms
      _invalid -> raise "BNEST_BACKUP_TIMEOUT_MS must be an integer between 60000 and 7200000"
    end
end

# Deployment always passes VAPID values to both slots (tech-doc 007), even
# during the compatibility release where `BNEST_FAMILY_CHAT_ENABLED=false` --
# so this is unconditional in :prod, not gated on the feature flag, and
# fails closed rather than silently leaving push unavailable in production.
if config_env() == :prod do
  push = BnestApp.RuntimeSettings.push_config!(env)
  public_key = push.public_key
  private_key = push.private_key
  subject = push.subject

  # `WebPush.Vapid.authorization_header/1` (the `web_push` dependency) reads
  # this exact `:web_push, :vapid` config itself -- setting it here, rather
  # than a separate `:bnest_app` key, is the single source of truth so
  # `PushNotifications.configuration/0`'s availability check and the real
  # signing path in `PushNotifications.Adapters.WebPushSender` can never drift
  # apart.
  config :web_push, :vapid, public_key: public_key, private_key: private_key, subject: subject
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :bnest_app, BnestAppWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/bnest_app_web/router\.ex$",
        ~r"lib/bnest_app_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base = BnestApp.RuntimeSettings.secret_key_base!(env)

  host = BnestApp.RuntimeSettings.phx_host(env)

  config :bnest_app, :dns_cluster_query, BnestApp.RuntimeSettings.dns_cluster_query(env)

  config :bnest_app, BnestAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {127, 0, 0, 1}],
    secret_key_base: secret_key_base

  config :bnest_app, :session_cookie,
    key: "_bnest_identity",
    secure: true,
    same_site: "Lax",
    max_age: 60 * 60 * 24 * 365 * 20

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :bnest_app, BnestAppWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :bnest_app, BnestAppWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :bnest_app, BnestApp.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
