defmodule Observer.Web.Components.Core do
  @moduledoc """
  Provides core UI components.
  """
  use Observer.Web, :html

  alias Phoenix.HTML.Form

  @doc ~S"""
  Renders a table with generic metric log styling.

  ## Examples

      <.table_tracing id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table_tracing>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"
  attr :transition, :boolean, default: false

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col slots"

  slot :col, required: true do
    attr :label, :string
  end

  def table_tracing(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="px-4 sm:overflow-visible sm:px-0 ">
      <div id={"#{@id}-table"} class="block" phx-hook="ScrollBottom">
        <table class="items-center w-full border-collapse ">
          <thead class="text-xs text-left align-middle leading-6 text-blueGray-500 uppercase sticky top-0 z-10">
            <tr>
              <th :for={col <- @col} class="p-1 pb-1 pr-6 font-semibold font-normal">
                {col[:label]}
              </th>
            </tr>
          </thead>
          <tbody
            id={"#{@id}-tbody"}
            phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
            class=" relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700 dark:text-zinc-100"
          >
            <tr
              :for={row <- @rows}
              id={@row_id && @row_id.(row)}
              class="group bg-white dark:bg-gray-800 "
              phx-mounted={
                @transition &&
                  JS.transition(
                    {"first:ease-in duration-300", "first:opacity-0 first:p-0 first:h-0",
                     "first:opacity-100"},
                    time: 100
                  )
              }
            >
              <td
                :for={{col, i} <- Enum.with_index(@col)}
                phx-click={@row_click && @row_click.(row)}
                class={[
                  "relative p-0 text-base-content/90 max-w-md ",
                  @row_click && "hover:cursor-pointer"
                ]}
              >
                <div class="block px-1 py-1 pr-6 text-xs font-mono ">
                  <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 dark:group-hover:bg-zinc-700 sm:rounded-l-xl" />
                  <span class={[
                    "relative",
                    i == 0 && "whitespace-nowrap font-semibold text-zinc-900 dark:text-zinc-100"
                  ]}>
                    {render_slot(col, @row_item.(row))}
                  </span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @doc ~S"""
  Renders a table with process styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"
  attr :transition, :boolean, default: false
  attr :title_bg_color, :string, default: "standard"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col slots"

  slot :col, required: true do
    attr :label, :string
  end

  def table_process(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="px-4 sm:overflow-visible sm:px-0 rounded bg-white dark:bg-gray-800 border border-solid border-blueGray-100">
      <div id={"#{@id}-table"} class="block max-h-[600px]">
        <table class="items-center w-full border-collapse">
          <div class={[
            "text-center text-sm font-mono font-semibold rounded-t px-6 py-1",
            title_bg_color(@title_bg_color)
          ]}>
            {@title}
          </div>
          <tbody
            id={"#{@id}-tbody"}
            phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
            class=" relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700 dark:text-zinc-200"
          >
            <tr
              :for={row <- @rows}
              id={@row_id && @row_id.(row)}
              class="group hover:bg-zinc-50"
              phx-mounted={
                @transition &&
                  JS.transition(
                    {"first:ease-in duration-300", "first:opacity-0 first:p-0 first:h-0",
                     "first:opacity-100"},
                    time: 100
                  )
              }
            >
              <td
                :for={{col, i} <- Enum.with_index(@col)}
                phx-click={@row_click && @row_click.(row)}
                class={["relative p-0", @row_click && "hover:cursor-pointer"]}
              >
                <div class="block px-1 py-1 pr-6 text-xs font-mono ">
                  <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 dark:group-hover:bg-zinc-700 sm:rounded-l-xl" />
                  <span class={[
                    "relative",
                    i == 0 && "font-semibold text-zinc-900 dark:text-zinc-300"
                  ]}>
                    {render_slot(col, @row_item.(row))}
                  </span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp title_bg_color("liveview"), do: "bg-green-200 dark:bg-green-900"
  defp title_bg_color(_any), do: "bg-zinc-200 dark:bg-zinc-500"

  @doc ~S"""
  Renders a table with generic metrics styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"
  attr :transition, :boolean, default: false
  attr :h_max_size, :string, default: "h-64"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  def table_metrics(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="px-4 sm:overflow-visible sm:px-0">
      <div
        id={"#{@id}-table"}
        class={["block overflow-y-auto", "#{@h_max_size}"]}
        phx-hook="ScrollBottom"
      >
        <table class="items-center w-full border-collapse">
          <thead class="text-xs text-left align-middle leading-6 bg-white bg-blueGray-50 dark:bg-gray-800 text-blueGray-500 dark:text-blueGray-700 uppercase sticky top-0 z-10">
            <tr>
              <th :for={col <- @col} class="p-1 pb-1 pr-6 font-semibold font-normal">
                {col[:label]}
              </th>
            </tr>
          </thead>
          <tbody
            id={@id}
            phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
            class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700 dark:text-neutral-400"
          >
            <tr
              :for={row <- @rows}
              id={@row_id && @row_id.(row)}
              class="group hover:bg-zinc-50"
              phx-mounted={
                @transition &&
                  JS.transition(
                    {"last:ease-in duration-300", "last:opacity-0 last:p-0 last:h-0",
                     "last:opacity-100"},
                    time: 300
                  )
              }
            >
              <td
                :for={{col, i} <- Enum.with_index(@col)}
                phx-click={@row_click && @row_click.(row)}
                class={["relative p-0", @row_click && "hover:cursor-pointer"]}
              >
                <div class="block px-1 py-1 pr-6 text-xs font-mono ">
                  <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 dark:group-hover:bg-zinc-700 sm:rounded-l-xl" />
                  <span class={[
                    "relative",
                    i == 0 && "font-semibold text-zinc-900 dark:text-zinc-100"
                  ]}>
                    {render_slot(col, @row_item.(row))}
                  </span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values:
      ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week select-undefined-class text-custom-search)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center bg-white dark:bg-gray-800 gap-4 text-sm leading-6 text-zinc-600">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-zinc-300 focus:ring-0"
          {@rest}
        /> {@label}
      </label>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class="mt-2 block bg-white dark:bg-gray-800  w-full rounded-md border border-gray-300 shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @value)}
      </select>
    </div>
    """
  end

  def input(%{type: "select-undefined-class"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <select id={@id} name={@name} multiple={@multiple} {@rest}>
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @value)}
      </select>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block bg-white dark:bg-gray-800  w-full rounded-lg focus:ring-0 sm:text-sm sm:leading-6",
          "min-h-[6rem] phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      ><%= Form.normalize_value("textarea", @value) %></textarea>
    </div>
    """
  end

  def input(%{type: "text-custom-search"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <input
        type="text"
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        class={[
          "ml-2 mr-2 h-2 bg-white dark:bg-gray-800  block rounded-lg focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        class={[
          "mt-2 block bg-white dark:bg-gray-800 w-full rounded-lg focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
    </div>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, _opts}) do
    msg
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Renders a tooltip around a given inner element.

  ## Assigns
    * `:label` - The text to show inside the tooltip.
    * `:position` - Optional, one of `:top`, `:bottom`, `:left`, `:right`. Defaults to `:top`.
  """
  attr :label, :string, required: true
  attr :position, :atom, default: :bottom
  slot :inner_block, required: true

  def tooltip(assigns) do
    ~H"""
    <div class="relative inline-flex group max-w-full">
      {render_slot(@inner_block)}

      <div class={
    tooltip_position_class(@position) <>
    " hidden group-hover:flex opacity-0 group-hover:opacity-100 transition-opacity duration-150 bg-white dark:bg-gray-600 text-gray-800 dark:text-gray-200 text-xs rounded py-1 px-2 z-50 max-w-[90vw] text-left whitespace-pre-line break-words"
    }>
        {@label}
      </div>
    </div>
    """
  end

  # Helper to handle tooltip positioning
  defp tooltip_position_class(:top),
    do: "absolute bottom-full left-1/2 -translate-x-1/2 mb-2"

  defp tooltip_position_class(:bottom),
    do: "absolute top-full left-1/2 -translate-x-1/2 mt-2"

  defp tooltip_position_class(:left),
    do: "absolute right-full top-1/2 -translate-y-1/2 mr-2"

  defp tooltip_position_class(:right),
    do: "absolute left-full top-1/2 -translate-y-1/2 ml-2"
end
