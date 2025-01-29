defmodule Tracing.Web.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Tracing.Web.Case
      import Phoenix.LiveViewTest

      @endpoint Tracing.Web.Endpoint
    end
  end
end
