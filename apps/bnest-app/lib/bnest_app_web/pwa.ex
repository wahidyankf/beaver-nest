defmodule BnestAppWeb.Pwa do
  @moduledoc false

  def install_metadata do
    %{
      manifest_path: "/manifest.webmanifest",
      service_worker_path: "/service-worker.js",
      icon_paths: ["/images/beaver-nest-192.png", "/images/beaver-nest-512.png"]
    }
  end
end
