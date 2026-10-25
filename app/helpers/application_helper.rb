module ApplicationHelper
  def nav_link_to(name, path)
    classes = if request.path.start_with?(path)
      "text-lime-700 dark:text-[#6ACD12] font-medium"
    else
      "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
    end

    link_to name, path, class: classes
  end
end
