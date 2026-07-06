defmodule Observer.Web.Tracing.Selection do
  @moduledoc """
  Shared node/module/function selection state, used by both the Tracing page and the Profiling
  page - the two pages that let a user pick which functions to trace before running a session.
  """

  alias ObserverWeb.Tracer

  @type t :: %{
          services_keys: [String.t()],
          modules_keys: [String.t()],
          functions_keys: [String.t()],
          selected_services_keys: [String.t()],
          selected_modules_keys: [String.t()],
          selected_functions_keys: [String.t()],
          node: list()
        }

  @doc """
  Empty selection state. Does not call out to any node, so it's safe to use before the socket is
  connected (the disconnected/dead render).
  """
  @spec new :: t()
  def new do
    %{
      services_keys: [],
      modules_keys: [],
      functions_keys: [],
      selected_services_keys: [],
      selected_modules_keys: [],
      selected_functions_keys: [],
      node: []
    }
  end

  @doc """
  Rebuilds the selection state for the current cluster membership, given the currently selected
  keys. Only queries modules/functions for nodes/modules that are actually selected.
  """
  @spec update([String.t()], [String.t()], [String.t()]) :: t()
  def update(selected_services_keys, selected_modules_keys, selected_functions_keys) do
    initial_map = %{
      new()
      | selected_services_keys: selected_services_keys,
        selected_modules_keys: selected_modules_keys,
        selected_functions_keys: selected_functions_keys
    }

    Enum.reduce(Node.list() ++ [Node.self()], initial_map, fn instance_node,
                                                              %{
                                                                services_keys: services_keys,
                                                                modules_keys: modules_keys,
                                                                functions_keys: functions_keys,
                                                                node: node
                                                              } = acc ->
      service = instance_node |> to_string
      service_selected? = service in selected_services_keys

      [name, _hostname] = String.split(service, "@")
      services_keys = (services_keys ++ [service]) |> Enum.sort()

      instance_module_keys =
        if service_selected? do
          Tracer.get_modules(instance_node) |> Enum.map(&to_string/1)
        else
          []
        end

      {instance_functions_keys, functions} =
        Enum.reduce(instance_module_keys, {[], []}, fn module, {keys, fun} ->
          # credo:disable-for-lines:6
          if module in selected_modules_keys do
            module_functions_info =
              Tracer.get_module_functions_info(instance_node, String.to_existing_atom(module))

            function_keys = Map.keys(module_functions_info.functions) |> Enum.map(&to_string/1)
            {keys ++ function_keys, fun ++ [module_functions_info]}
          else
            {keys, fun}
          end
        end)

      modules_keys = (modules_keys ++ instance_module_keys) |> Enum.sort() |> Enum.uniq()
      functions_keys = (functions_keys ++ instance_functions_keys) |> Enum.sort() |> Enum.uniq()

      node =
        if service_selected? do
          [
            %{
              name: name,
              modules_keys: instance_module_keys,
              function_keys: instance_functions_keys,
              service: service,
              functions: functions
            }
            | node
          ]
        else
          node
        end

      %{
        acc
        | services_keys: services_keys,
          modules_keys: modules_keys,
          functions_keys: functions_keys,
          node: node
      }
    end)
  end

  @doc """
  Builds the `functions_by_node`-shaped list `ObserverWeb.Tracer.start_trace/2` expects, from the
  current selection. `match_spec_keys` is attached to every entry (the Tracing page passes the
  user-selected match specs; the Profiling page, which has no match-spec picker, passes `[]`).
  """
  @spec build_functions_to_monitor(t(), [String.t()]) :: list()
  def build_functions_to_monitor(node_info, match_spec_keys \\ []) do
    Enum.reduce(node_info.selected_services_keys, [], fn service_key, service_acc ->
      service_info = Enum.find(node_info.node, &(&1.service == service_key))

      service_acc ++
        Enum.reduce(node_info.selected_modules_keys, [], fn module_key, module_acc ->
          module_key_atom = String.to_existing_atom(module_key)

          node_functions_info =
            Enum.find(service_info.functions, &(&1.module == module_key_atom))

          functions =
            Enum.reduce(node_info.selected_functions_keys, [], fn function_key, function_acc ->
              function = Map.get(node_functions_info.functions, function_key, nil)

              # credo:disable-for-lines:14
              if module_key in service_info.modules_keys and function do
                function_acc ++
                  [
                    %{
                      node: String.to_existing_atom(service_key),
                      module: module_key_atom,
                      function: function.name,
                      arity: function.arity,
                      match_spec: match_spec_keys
                    }
                  ]
              else
                function_acc
              end
            end)

          # If the module doesn't have any of the requested functions the default is to
          # include the whole module
          if functions == [] do
            module_acc ++
              [
                %{
                  node: String.to_existing_atom(service_key),
                  module: module_key_atom,
                  function: :_,
                  arity: :_,
                  match_spec: match_spec_keys
                }
              ]
          else
            module_acc ++ functions
          end
        end)
    end)
  end
end
