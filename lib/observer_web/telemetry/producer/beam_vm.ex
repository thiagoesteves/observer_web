defmodule ObserverWeb.Telemetry.Producer.BeamVm do
  @moduledoc """
  This module contains the reporting functions for Beam VM
  """

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================
  def process do
    measurements = %{
      total: :erlang.system_info(:port_count),
      limit: :erlang.system_info(:port_limit)
    }

    :telemetry.execute([:vm, :port], measurements, %{})

    measurements = %{
      total: :erlang.system_info(:atom_count),
      limit: :erlang.system_info(:atom_limit)
    }

    :telemetry.execute([:vm, :atom], measurements, %{})

    measurements = %{
      total: :erlang.system_info(:process_count),
      limit: :erlang.system_info(:process_limit)
    }

    :telemetry.execute([:vm, :process], measurements, %{})

    :ok
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================
end
