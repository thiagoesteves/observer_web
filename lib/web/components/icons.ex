defmodule Observer.Web.Components.Icons do
  @moduledoc false
  use Observer.Web, :html

  # Helpers

  attr :name, :atom, required: true

  def content(assigns) do
    ~H"""
    <%= case @name do %>
      <% :logo -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="flex-shrink-0 w-12 h-12"
        >
          <path stroke="none" d="M0 0h24v24H0z" fill="none" /><path d="M20 18a2 2 0 1 0 -4 0a2 2 0 0 0 4 0z" /><path d="M8 18a2 2 0 1 0 -4 0a2 2 0 0 0 4 0z" /><path d="M8 6a2 2 0 1 0 -4 0a2 2 0 0 0 4 0z" /><path d="M20 6a2 2 0 1 0 -4 0a2 2 0 0 0 4 0z" /><path d="M6 8v8" /><path d="M18 16v-8" /><path d="M8 6h8" /><path d="M16 18h-8" /><path d="M7.5 7.5l9 9" /><path d="M7.5 16.5l9 -9" />
        </svg>
      <% :tracing -> %>
        <svg
          class="flex-shrink-0 w-5 h-5 mr-4 text-gray-900 dark:text-white"
          width="24px"
          height="24px"
          viewBox="0 0 256 256"
          version="1.1"
          fill="none"
          stroke="currentColor"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <g
            style="stroke: currentColor; stroke-width: 0; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: none; fill-rule: nonzero; opacity: 1;"
            transform="translate(1.4065934065934016 1.4065934065934016) scale(2.81 2.81)"
          >
            <path
              d="M 77.127 81.457 h -0.373 v -2 h 0.373 c 1.239 0 2.432 -0.371 3.446 -1.072 l 1.137 1.645 C 80.36 80.964 78.775 81.457 77.127 81.457 z M 72.11 81.457 h -4.645 v -2 h 4.645 V 81.457 z M 62.822 81.457 h -4.645 v -2 h 4.645 V 81.457 z M 53.534 81.457 H 48.89 v -2 h 4.645 V 81.457 z M 44.246 81.457 h -4.644 v -2 h 4.644 V 81.457 z M 34.958 81.457 h -4.644 v -2 h 4.644 V 81.457 z M 84.813 75.85 l -1.904 -0.609 c 0.19 -0.596 0.287 -1.218 0.287 -1.852 c 0 -0.708 -0.121 -1.403 -0.36 -2.064 l 1.881 -0.68 c 0.318 0.88 0.479 1.804 0.479 2.744 C 85.195 74.229 85.066 75.058 84.813 75.85 z M 80.386 68.269 c -0.972 -0.62 -2.099 -0.948 -3.259 -0.948 h -0.634 v -2 h 0.634 c 1.542 0 3.041 0.437 4.335 1.263 L 80.386 68.269 z M 71.849 67.32 h -4.644 v -2 h 4.644 V 67.32 z M 62.561 67.32 h -4.408 c -0.092 0 -0.183 -0.001 -0.272 -0.005 l 0.074 -1.998 l 0.198 0.003 h 4.408 V 67.32 z M 53.016 65.474 c -1.37 -1.132 -2.34 -2.705 -2.732 -4.43 l 1.951 -0.443 c 0.294 1.296 1.024 2.479 2.055 3.332 L 53.016 65.474 z M 52.642 56.707 l -1.814 -0.84 c 0.744 -1.607 2.02 -2.945 3.59 -3.768 l 0.928 1.771 C 54.162 54.49 53.202 55.497 52.642 56.707 z M 64.038 53.184 h -4.645 v -2 h 4.645 V 53.184 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
            <path
              d="M 21.094 27.868 C 9.444 27.868 0 37.311 0 48.961 c 0 5.201 1.891 9.954 5.011 13.632 l 16.082 18.941 l 16.082 -18.941 c 3.12 -3.678 5.011 -8.431 5.011 -13.632 C 42.187 37.311 32.743 27.868 21.094 27.868 z M 21.094 56.91 c -4.791 0 -8.675 -3.884 -8.675 -8.675 c 0 -4.791 3.884 -8.675 8.675 -8.675 s 8.675 3.884 8.675 8.675 C 29.768 53.026 25.885 56.91 21.094 56.91 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
            <path
              d="M 73.577 11.624 c -9.015 0 -16.323 7.308 -16.323 16.323 c 0 4.025 1.463 7.703 3.878 10.549 l 12.445 14.657 l 12.445 -14.657 c 2.415 -2.846 3.878 -6.524 3.878 -10.549 C 89.9 18.932 82.592 11.624 73.577 11.624 z M 73.577 34.098 c -3.707 0 -6.713 -3.006 -6.713 -6.713 c 0 -3.707 3.005 -6.713 6.713 -6.713 c 3.707 0 6.713 3.006 6.713 6.713 C 80.29 31.093 77.285 34.098 73.577 34.098 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
          </g>
        </svg>
      <% :metrics -> %>
        <svg
          class="flex-shrink-0 w-5 h-5 mr-4 text-gray-900 dark:text-white"
          width="24px"
          height="24px"
          viewBox="0 0 256 256"
          version="1.1"
          fill="none"
          stroke="currentColor"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <g
            style="stroke: currentColor; stroke-width: 0; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: none; fill-rule: nonzero; opacity: 1;"
            transform="translate(1.4065934065934016 1.4065934065934016) scale(2.81 2.81)"
          >
            <path
              d="M 12.312 90.235 c -0.829 0 -1.5 -0.672 -1.5 -1.5 v -87 c 0 -0.829 0.671 -1.5 1.5 -1.5 s 1.5 0.671 1.5 1.5 v 87 C 13.812 89.563 13.14 90.235 12.312 90.235 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
            <path
              d="M 89 79.924 H 2 c -0.829 0 -1.5 -0.672 -1.5 -1.5 s 0.671 -1.5 1.5 -1.5 h 87 c 0.828 0 1.5 0.672 1.5 1.5 S 89.828 79.924 89 79.924 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
            <path
              d="M 20.967 55.139 c -0.513 0 -1.013 -0.263 -1.292 -0.736 c -0.422 -0.714 -0.186 -1.633 0.528 -2.055 L 77.92 18.225 c 0.716 -0.42 1.635 -0.186 2.055 0.528 c 0.422 0.713 0.186 1.633 -0.527 2.054 L 21.729 54.93 C 21.49 55.071 21.227 55.139 20.967 55.139 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
            <path
              d="M 76.184 30.75 c -0.123 0 -0.249 -0.016 -0.374 -0.048 c -0.803 -0.206 -1.286 -1.023 -1.08 -1.826 l 2.128 -8.282 l -8.281 -2.128 c -0.803 -0.206 -1.286 -1.023 -1.08 -1.826 c 0.206 -0.802 1.022 -1.287 1.826 -1.08 l 9.734 2.501 c 0.803 0.206 1.286 1.023 1.08 1.826 l -2.501 9.734 C 77.462 30.3 76.852 30.75 76.184 30.75 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
            <path
              d="M 29.677 67.234 h -9.142 c -0.733 0 -1.328 0.594 -1.328 1.328 V 79.17 h 11.798 V 68.562 C 31.005 67.828 30.41 67.234 29.677 67.234 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
            <path
              d="M 46.592 57.348 H 37.45 c -0.733 0 -1.328 0.594 -1.328 1.328 V 79.17 H 47.92 V 58.675 C 47.92 57.942 47.326 57.348 46.592 57.348 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
            <path
              d="M 63.508 47.461 h -9.142 c -0.733 0 -1.328 0.594 -1.328 1.328 V 79.17 h 11.798 V 48.789 C 64.835 48.056 64.241 47.461 63.508 47.461 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
            <path
              d="M 80.423 37.575 h -9.142 c -0.733 0 -1.328 0.594 -1.328 1.328 V 79.17 h 11.798 V 38.903 C 81.751 38.169 81.156 37.575 80.423 37.575 z"
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform=" matrix(1 0 0 1 0 0) "
              stroke-linecap="round"
            />
          </g>
        </svg>
      <% :applications -> %>
        <svg
          class="flex-shrink-0 w-5 h-5 mr-4 text-gray-900 dark:text-white"
          width="24px"
          height="24px"
          viewBox="0 0 512 512"
          xmlns="http://www.w3.org/2000/svg"
          version="1.1"
          fill="currentColor"
          stroke="currentColor"
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
        >
          <g>
            <path
              class="st0"
              d="M332.998,291.918c52.2-71.895,45.941-173.338-18.834-238.123c-71.736-71.728-188.468-71.728-260.195,0
    c-71.746,71.745-71.746,188.458,0,260.204c64.775,64.775,166.218,71.034,238.104,18.844l14.222,14.203l40.916-40.916
    L332.998,291.918z M278.488,278.333c-52.144,52.134-136.699,52.144-188.852,0c-52.152-52.153-52.152-136.717,0-188.861
    c52.154-52.144,136.708-52.144,188.852,0C330.64,141.616,330.64,226.18,278.488,278.333z"
            />
            <path
              class="st0"
              d="M109.303,119.216c-27.078,34.788-29.324,82.646-6.756,119.614c2.142,3.489,6.709,4.603,10.208,2.46
    c3.49-2.142,4.594-6.709,2.462-10.198v0.008c-19.387-31.7-17.45-72.962,5.782-102.771c2.526-3.228,1.946-7.898-1.292-10.405
    C116.48,115.399,111.811,115.979,109.303,119.216z"
            />
            <path
              class="st0"
              d="M501.499,438.591L363.341,315.178l-47.98,47.98l123.403,138.168c12.548,16.234,35.144,13.848,55.447-6.456
    C514.505,474.576,517.743,451.138,501.499,438.591z"
            />
          </g>
        </svg>
      <% :root -> %>
        <svg
          class="flex-shrink-0 w-5 h-5 mr-4 text-gray-900 dark:text-white"
          width="256"
          height="256"
          viewBox="0 0 256 256"
          xmlns="http://www.w3.org/2000/svg"
          version="1.1"
          fill="currentColor"
          stroke="currentColor"
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
        >
          <g
            style="stroke: currentColor; stroke-width: 0; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: none; fill-rule: nonzero; opacity: 1;"
            transform="translate(1.4065934065934016 1.4065934065934016) scale(2.81 2.81)"
          >
            <polygon
              points="75.96,30.96 75.96,13.34 67.26,13.34 67.26,22.26 45,0 0.99,44.02 7.13,50.15 45,12.28 82.88,50.15 89.01,44.02 "
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform="  matrix(1 0 0 1 0 0) "
            />
            <polygon
              points="45,20 14.04,50.95 14.04,90 35.29,90 35.29,63.14 54.71,63.14 54.71,90 75.96,90 75.96,50.95 "
              style="stroke: currentColor; stroke-width: 1; stroke-dasharray: none; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 10; fill: currentColor; fill-rule: nonzero; opacity: 1;"
              transform="  matrix(1 0 0 1 0 0) "
            />
          </g>
        </svg>
    <% end %>
    """
  end

  attr :rest, :global,
    default: %{
      "stroke-width": "1.5",
      class: "w-6 h-6",
      fill: "none",
      stroke: "currentColor",
      viewBox: "0 0 24 24"
    }

  slot :inner_block, required: true

  defp svg_outline(assigns) do
    ~H"""
    <svg {@rest}>
      {render_slot(@inner_block)}
    </svg>
    """
  end

  attr :rest, :global

  def check_circle(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </.svg_outline>
    """
  end

  attr :rest, :global

  def x_mark(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
    </.svg_outline>
    """
  end

  attr :rest, :global

  def x_circle(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </.svg_outline>
    """
  end

  attr :rest, :global

  def moon(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M17.715 15.15A6.5 6.5 0 0 1 9 6.035C6.106 6.922 4 9.645 4 12.867c0 3.94 3.153 7.136 7.042 7.136 3.101 0 5.734-2.032 6.673-4.853Z">
      </path>
    </.svg_outline>
    """
  end

  attr :rest, :global

  def sun(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M12 3v2.25m6.364.386l-1.591 1.591M21 12h-2.25m-.386 6.364l-1.591-1.591M12 18.75V21m-4.773-4.227l-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0z"
      />
    </.svg_outline>
    """
  end

  attr :rest, :global

  def computer_desktop(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M9 17.25v1.007a3 3 0 01-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0115 18.257V17.25m6-12V15a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 15V5.25m18 0A2.25 2.25 0 0018.75 3H5.25A2.25 2.25 0 003 5.25m18 0V12a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 12V5.25"
      />
    </.svg_outline>
    """
  end
end
