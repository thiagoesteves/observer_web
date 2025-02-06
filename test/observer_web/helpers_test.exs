defmodule Observer.Web.HelpersTest do
  use ExUnit.Case, async: true

  alias Observer.Web.Helpers

  describe "encode_params/1" do
    import Helpers, only: [encode_params: 1]

    test "encoding fields with multiple values" do
      assert [nodes: "web-1,web-2"] = encode_params(nodes: ~w(web-1 web-2))
    end

    test "encoding fields with path qualifiers" do
      assert [args: "a++x"] = encode_params(args: [~w(a), "x"])
      assert [args: "a,b++x"] = encode_params(args: [~w(a b), "x"])
      assert [args: "a,b,c++x"] = encode_params(args: [~w(a b c), "x"])
    end
  end
end
