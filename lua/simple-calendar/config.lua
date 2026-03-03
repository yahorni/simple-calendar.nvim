local M = {}

-- Default config
M._config = {
    daily_path_pattern = "",
    highlight_unfinished_tasks = false,
    completed_task_markers = { "x", "-" },
}

-- Global constants
M.MONTH_NAMES = { "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December" }
M.WEEKDAYS_HEADER = "Mo Tu We Th Fr Sa Su"

return M
