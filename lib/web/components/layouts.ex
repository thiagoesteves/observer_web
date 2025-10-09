defmodule Observer.Web.Layouts do
  @moduledoc """
  This module provides layouts

  ## References:
   * https://github.com/oban-bg/oban_web/blob/main/lib/oban/web/components/layouts.ex
  """
  use Observer.Web, :html

  alias Observer.Web.Components.Icons

  phoenix_js_paths =
    for app <- ~w(phoenix phoenix_html phoenix_live_view)a do
      path = Application.app_dir(app, ["priv", "static", "#{app}.js"])
      Module.put_attribute(__MODULE__, :external_resource, path)
      path
    end

  @static_path Application.app_dir(:observer_web, ["priv", "static"])

  @external_resource css_path = Path.join(@static_path, "app.css")
  @external_resource js_path = Path.join(@static_path, "app.js")

  @css File.read!(css_path)

  @js """
  #{for path <- phoenix_js_paths, do: path |> File.read!() |> String.replace("//# sourceMappingURL=", "// ")}
  #{File.read!(js_path)}
  """

  def render("app.css"), do: @css
  def render("app.js"), do: @js

  embed_templates "layouts/*"

  def logo(assigns) do
    ~H"""
    <a href={observer_path(:tracing, @params)} class="flex" title="Observer Web">
      <div>
        <Icons.content name={:logo} />
      </div>
      <h3 class="class ml-2 items-center tracking-tight text-gray-900">
        <span class="block text-4xl font-oswald">
          Observer
          <span class="text-transparent text-4xl font-bold bg-clip-text bg-gradient-to-tr to-cyan-500 from-blue-600">
            WEB
          </span>
        </span>
      </h3>
    </a>
    """
  end

  def nav(assigns) do
    ~H"""
    <nav class="flex space-x-1">
      <.link
        :for={page <- list_pages_by_params(@params)}
        class={link_class(@page, page)}
        data-shortcut={JS.navigate(observer_path(page, @params))}
        id={"nav-#{page}"}
        navigate={observer_path(page, @params)}
        title={"Navigate to #{String.capitalize(to_string(page))}"}
      >
        <Icons.content name={page} />
        {String.upcase(to_string(page))}
      </.link>
    </nav>
    """
  end

  def footer(assigns) do
    assigns =
      assign(assigns,
        oss_version: Application.spec(:observer_web, :vsn)
      )

    ~H"""
    <footer class="flex flex-col px-3 py-6 text-sm justify-center items-center md:flex-row">
      <.version name="Observer Web" version={@oss_version} />

      <span class="text-gray-800 dark:text-gray-200 font-semibold">
        Made by
        <a
          href="https://www.linkedin.com/in/thiago-cesar-calori-esteves-972368115/"
          class="font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline"
        >
          Thiago Esteves
        </a>
      </span>
    </footer>
    """
  end

  attr :name, :string
  attr :version, :string

  defp version(assigns) do
    ~H"""
    <span class="text-gray-600 dark:text-gray-400 tabular mr-0 mb-1 md:mr-3 md:mb-0">
      {@name} {if @version, do: "v#{@version}", else: "–"}
    </span>
    """
  end

  defp link_class(curr, page) do
    base =
      "flex items-center px-4 py-2.5 text-sm font-bold transition-all duration-200 text-gray-900 rounded-lg group"

    if curr == page do
      base <> " bg-gray-100"
    else
      base <> " hover:text-white hover:bg-indigo-500"
    end
  end

  defp list_pages_by_params(%{"iframe" => "true"}), do: [:tracing, :applications, :metrics]
  defp list_pages_by_params(_params), do: [:root, :tracing, :applications, :metrics]
end
