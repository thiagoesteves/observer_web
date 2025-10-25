defmodule ObserverWeb.Monitor do
  @moduledoc """
  This module will provide process/port monitor context
  """

  alias ObserverWeb.Monitor.ProcessPort

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Starts monitoring a process/port memory usage
  """
  @spec start_id_monitor(pid_or_port :: pid() | port()) ::
          {:ok, ObserverWeb.Monitor.ProcessPort.t()}
  def start_id_monitor(pid_or_port), do: ProcessPort.start_id_monitor(pid_or_port)

  @doc """
  Stops monitoring a process/port memory usage
  """
  @spec stop_id_monitor(pid_or_port :: pid() | port()) :: :ok
  def stop_id_monitor(pid_or_port), do: ProcessPort.stop_id_monitor(pid_or_port)

  @doc """
  Checks if memory monitoring is enabled for a process/port
  """
  @spec id_info(pid_or_port :: pid() | port()) ::
          {:ok, ObserverWeb.Monitor.ProcessPort.t()} | {:error, :not_found | :rescued}
  def id_info(pid_or_port), do: ProcessPort.id_info(pid_or_port)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
