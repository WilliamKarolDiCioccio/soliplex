import fastapi


class UnknownThread(fastapi.HTTPException):
    def __init__(self, user_name: str, thread_id: str):
        self.user_name = user_name
        self.thread_id = thread_id
        message = f"Unknown thread: UUID {thread_id} for user {user_name}"
        super().__init__(status_code=404, detail=message)


class UnknownRun(ValueError):
    def __init__(self, run_id: str):
        self.run_id = run_id
        super().__init__(f"Run input run ID {run_id} does not exist in thread")


class MissingParentRun(ValueError):
    def __init__(self, parent_run_id: str):
        self.parent_run_id = parent_run_id
        super().__init__(
            f"Run input parent run ID {parent_run_id} does not exist in thread"
        )


class RunInputMismatch(ValueError):
    def __init__(self, which: str):
        self.which = which
        super().__init__(f"Run input field does not match run: {which}")
