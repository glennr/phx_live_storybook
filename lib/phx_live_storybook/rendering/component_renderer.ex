defmodule PhxLiveStorybook.Rendering.ComponentRenderer do
  @moduledoc """
  Responsible for rendering your function & live components, for a given
  `PhxLiveStorybook.Story` or `PhxLiveStorybook.StoryGroup`.
  """

  alias Phoenix.LiveView.Engine, as: LiveViewEngine
  alias Phoenix.LiveView.HTMLEngine
  alias PhxLiveStorybook.{Story, StoryGroup}

  @doc """
  Renders a story or a group of story for a component.
  """
  def render_story(fun_or_mod, story = %Story{}, extra_assigns, opts) do
    heex =
      component_heex(
        fun_or_mod,
        Map.merge(story.attributes, extra_assigns),
        story.block,
        story.slots
      )

    render_component_heex(fun_or_mod, heex, opts)
  end

  def render_story(fun_or_mod, %StoryGroup{stories: stories}, extra_assigns, opts) do
    heex =
      for story = %Story{id: story_id} <- stories, into: "" do
        extra_assigns = %{extra_assigns | id: "#{extra_assigns.id}-#{story_id}"}

        component_heex(
          fun_or_mod,
          Map.merge(story.attributes, extra_assigns),
          story.block,
          story.slots
        )
      end

    render_component_heex(fun_or_mod, heex, opts)
  end

  def render_story_within_template(template, fun_or_mod, story = %Story{}, extra_assigns, opts) do
    heex =
      template_heex(
        template,
        story.id,
        fun_or_mod,
        Map.merge(story.attributes, extra_assigns),
        story.block,
        story.slots
      )

    render_component_heex(fun_or_mod, heex, opts)
  end

  def render_story_within_template(
        template,
        fun_or_mod,
        %StoryGroup{id: group_id, stories: stories},
        group_extra_assigns,
        opts
      ) do
    heex =
      for story = %Story{id: story_id} <- stories, into: "" do
        extra_assigns = Map.get(group_extra_assigns, story_id)

        template_heex(
          template,
          "#{group_id}:#{story_id}",
          fun_or_mod,
          Map.merge(story.attributes, extra_assigns),
          story.block,
          story.slots
        )
      end

    render_component_heex(fun_or_mod, heex, opts)
  end

  @doc """
  Renders a component.
  """
  def render_component(fun_or_mod, assigns, block, slots, opts) do
    heex = component_heex(fun_or_mod, assigns, block, slots)
    render_component_heex(fun_or_mod, heex, opts)
  end

  @doc """
  Renders a component.
  """
  def render_component_within_template(template, id, fun_or_mod, assigns, block, slots, opts) do
    heex =
      template_heex(
        template,
        id,
        fun_or_mod,
        assigns,
        block,
        slots
      )

    render_component_heex(fun_or_mod, heex, opts)
  end

  defp component_heex(fun, assigns, nil, []) when is_function(fun) do
    """
    <.#{function_name(fun)} #{attributes_markup(assigns)}/>
    """
  end

  defp component_heex(fun, assigns, block, slots) when is_function(fun) do
    """
    <.#{function_name(fun)} #{attributes_markup(assigns)}>
      #{block}
      #{slots}
    </.#{function_name(fun)}>
    """
  end

  defp component_heex(module, assigns, nil, []) when is_atom(module) do
    """
    <.live_component module={#{inspect(module)}} #{attributes_markup(assigns)}/>
    """
  end

  defp component_heex(module, assigns, block, slots) when is_atom(module) do
    """
    <.live_component module={#{inspect(module)}} #{attributes_markup(assigns)}>
      #{block}
      #{slots}
    </.live_component>
    """
  end

  defp template_heex(template, story_id, fun_or_mod, assigns, block, slots) do
    template
    |> String.replace(":story_id", to_string(story_id))
    |> String.replace(
      ~r|<\.story[^\/]*\/>|,
      component_heex(fun_or_mod, assigns, block, slots)
    )
  end

  defp attributes_markup(attributes) do
    Enum.map_join(attributes, " ", fn
      {name, val} when is_binary(val) -> ~s|#{name}="#{val}"|
      {name, val} -> ~s|#{name}={#{inspect(val, structs: false)}}|
    end)
  end

  defp render_component_heex(fun_or_mod, heex, opts) do
    quoted_code = EEx.compile_string(heex, engine: HTMLEngine)

    {evaluated, _} =
      Code.eval_quoted(quoted_code, [assigns: []],
        requires: [Kernel],
        aliases: eval_quoted_aliases(opts, fun_or_mod),
        functions: eval_quoted_functions(opts, fun_or_mod)
      )

    LiveViewEngine.live_to_iodata(evaluated)
  end

  defp eval_quoted_aliases(opts, fun_or_mod) do
    aliases = Keyword.get(opts, :aliases, [])
    eval_quoted_aliases([module(fun_or_mod) | aliases])
  end

  defp eval_quoted_aliases(modules) do
    for mod <- modules, reduce: [] do
      aliases ->
        alias_name = :"Elixir.#{mod |> Module.split() |> Enum.at(-1) |> String.to_atom()}"

        if alias_name == mod do
          aliases
        else
          [{alias_name, mod} | aliases]
        end
    end
  end

  defp eval_quoted_functions(opts, fun) when is_function(fun) do
    [
      {Phoenix.LiveView.Helpers, [live_file_input: 2]},
      {function_module(fun), [{function_name(fun), 1}]}
    ] ++ extra_imports(opts)
  end

  defp eval_quoted_functions(opts, mod) when is_atom(mod) do
    [
      {Phoenix.LiveView.Helpers, [live_component: 1, live_file_input: 2]}
    ] ++ extra_imports(opts)
  end

  defp extra_imports(opts), do: Keyword.get(opts, :imports, [])

  defp module(fun) when is_function(fun), do: function_module(fun)
  defp module(mod) when is_atom(mod), do: mod

  defp function_module(fun), do: Function.info(fun)[:module]
  defp function_name(fun), do: Function.info(fun)[:name]
end
