#!/usr/bin/env python3
"""Tkinter desktop frontend for PDF-Protecter."""

from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox

from pdf_protecter import PdfSafeError, change_container_password, create_container, open_container_status


W = 980
H = 680
SIDEBAR_W = 250
BG = "#edf1f6"
SIDEBAR = "#111827"
SIDEBAR_SOFT = "#1f2937"
CARD = "#ffffff"
TEXT = "#111827"
MUTED = "#667085"
LINE = "#d7dee8"
FIELD = "#f8fafc"
BLUE = "#2563eb"
BLUE_DARK = "#1d4ed8"


class PdfProtecterApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("PDF-Protecter - PDF 安全容器")
        self.geometry(f"{W}x{H}")
        self.minsize(W, H)
        self.maxsize(W, H)
        self.configure(bg=BG)

        self.page = "create"
        self.nav_buttons: dict[str, tk.Label] = {}
        self.form_widgets: list[tk.Widget] = []
        self.vars: dict[str, tk.Variable] = {}
        self.status = tk.StringVar(value="准备就绪")

        self.canvas = tk.Canvas(self, width=W, height=H, bg=BG, highlightthickness=0)
        self.canvas.place(x=0, y=0, width=W, height=H)
        self._draw_shell()
        self.show_page("create")

    def _draw_shell(self) -> None:
        self.canvas.create_rectangle(0, 0, SIDEBAR_W, H, fill=SIDEBAR, outline="")
        self.canvas.create_oval(28, 32, 72, 76, fill=BLUE, outline="")
        self.canvas.create_text(50, 54, text="PDF", fill="#ffffff", font=("Helvetica", 10, "bold"))
        self.canvas.create_text(28, 104, text="PDF-Protecter", anchor="w", fill="#ffffff", font=("Helvetica", 21, "bold"))
        self.canvas.create_text(28, 132, text="PDF 安全容器", anchor="w", fill="#98a2b3", font=("Helvetica", 12))

        self._nav("create", "保护 PDF", "加密真实文件并设置伪装 PDF", 178)
        self._nav("open", "打开容器", "按密码导出真实或伪装文件", 252)
        self._nav("password", "修改密码", "更新密码或替换伪装 PDF", 326)

        self.canvas.create_text(
            28,
            590,
            text="本地处理，不上传文件\n错误密码可导出伪装 PDF\n可设置 3 次错误后销毁真实内容",
            anchor="w",
            fill="#98a2b3",
            font=("Helvetica", 11),
            justify="left",
        )

    def _nav(self, key: str, title: str, subtitle: str, y: int) -> None:
        button = tk.Label(self, text="", bg=SIDEBAR, cursor="pointinghand")
        button.place(x=16, y=y, width=218, height=60)
        button.bind("<Button-1>", lambda _event: self.show_page(key))
        self.nav_buttons[key] = button
        self.canvas.create_text(34, y + 18, text=title, anchor="w", fill="#ffffff", font=("Helvetica", 13, "bold"))
        self.canvas.create_text(34, y + 40, text=subtitle, anchor="w", fill="#98a2b3", font=("Helvetica", 10))

    def show_page(self, key: str) -> None:
        self.page = key
        for nav_key, button in self.nav_buttons.items():
            button.configure(bg=BLUE if nav_key == key else SIDEBAR)
        self._clear_form()
        if key == "create":
            self._create_page()
        elif key == "open":
            self._open_page()
        else:
            self._password_page()

    def _clear_form(self) -> None:
        for widget in self.form_widgets:
            widget.destroy()
        self.form_widgets.clear()
        self.canvas.delete("content")
        self.vars.clear()
        self.status.set("准备就绪")

    def _content_header(self, eyebrow: str, title: str, subtitle: str) -> None:
        self.canvas.create_text(290, 60, text=eyebrow, anchor="w", fill=BLUE, font=("Helvetica", 12, "bold"), tags="content")
        self.canvas.create_text(290, 98, text=title, anchor="w", fill=TEXT, font=("Helvetica", 31, "bold"), tags="content")
        self.canvas.create_text(290, 134, text=subtitle, anchor="w", fill=MUTED, font=("Helvetica", 13), tags="content")
        self.canvas.create_rectangle(290, 180, 940, 604, fill=CARD, outline=LINE, tags="content")

    def _field(self, key: str, label: str, y: int, button_text: str | None = None, command: object | None = None) -> None:
        self.vars[key] = tk.StringVar()
        self.canvas.create_text(322, y + 18, text=label, anchor="w", fill=TEXT, font=("Helvetica", 12, "bold"), tags="content")
        entry = tk.Entry(self, textvariable=self.vars[key], bg=FIELD, fg=TEXT, relief="solid", bd=1, font=("Helvetica", 12))
        entry.place(x=430, y=y, width=370 if button_text else 470, height=40)
        self.form_widgets.append(entry)
        if button_text and command:
            button = self._button(button_text, command, 820, y, 86, 40, bg="#e8eef8", fg=TEXT)
            self.form_widgets.append(button)

    def _password(self, key: str, label: str, y: int) -> None:
        self.vars[key] = tk.StringVar()
        show_var = tk.BooleanVar(value=False)
        self.canvas.create_text(322, y + 18, text=label, anchor="w", fill=TEXT, font=("Helvetica", 12, "bold"), tags="content")
        entry = tk.Entry(
            self,
            textvariable=self.vars[key],
            show="*",
            bg=FIELD,
            fg=TEXT,
            relief="solid",
            bd=1,
            font=("Helvetica", 12),
        )
        entry.place(x=430, y=y, width=370, height=40)
        check = tk.Checkbutton(
            self,
            text="显示",
            variable=show_var,
            bg=CARD,
            fg=MUTED,
            command=lambda: entry.configure(show="" if show_var.get() else "*"),
        )
        check.place(x=820, y=y + 6, width=86, height=28)
        self.form_widgets.extend([entry, check])

    def _button(self, text: str, command: object, x: int, y: int, width: int, height: int, bg: str = BLUE, fg: str = "#ffffff") -> tk.Label:
        label = tk.Label(self, text=text, bg=bg, fg=fg, font=("Helvetica", 12, "bold"), cursor="pointinghand")
        label.place(x=x, y=y, width=width, height=height)
        label.bind("<Button-1>", lambda _event: command())
        label.bind("<Enter>", lambda _event: label.configure(bg=BLUE_DARK if bg == BLUE else "#dbe7fb"))
        label.bind("<Leave>", lambda _event: label.configure(bg=bg))
        return label

    def _footer(self, y: int, button_text: str, command: object) -> None:
        self.canvas.create_line(322, y, 908, y, fill="#edf0f5", tags="content")
        status = tk.Label(self, textvariable=self.status, bg=CARD, fg=MUTED, anchor="w", font=("Helvetica", 12))
        status.place(x=322, y=y + 30, width=410, height=34)
        button = self._button(button_text, command, 760, y + 26, 148, 44)
        self.form_widgets.extend([status, button])

    def _create_page(self) -> None:
        self._content_header(
            "CREATE CONTAINER",
            "保护 PDF",
            "把真实 PDF 和伪装 PDF 打包成一个安全容器，密码错误时只导出伪装 PDF。",
        )
        self._field("real", "真实 PDF", 220, "选择", self._choose_real)
        self._field("decoy", "伪装 PDF", 276, "选择", self._choose_decoy)
        self._field("out", "保存为", 332, "另存为", self._choose_create_out)
        self._password("password", "访问密码", 400)
        self._password("confirm", "确认密码", 456)

        self.vars["destruct"] = tk.BooleanVar(value=True)
        self.vars["destruct_after"] = tk.IntVar(value=3)
        self.canvas.create_text(322, 532, text="错误策略", anchor="w", fill=TEXT, font=("Helvetica", 12, "bold"), tags="content")
        check = tk.Checkbutton(
            self,
            text="密码错误达到次数后销毁容器内真实内容",
            variable=self.vars["destruct"],
            bg=CARD,
            fg=TEXT,
            font=("Helvetica", 12),
        )
        check.place(x=430, y=518, width=300, height=34)
        spin = tk.Spinbox(self, from_=1, to=20, textvariable=self.vars["destruct_after"], font=("Helvetica", 12), width=4)
        spin.place(x=738, y=520, width=56, height=30)
        self.canvas.create_text(804, 535, text="次", anchor="w", fill=MUTED, font=("Helvetica", 12), tags="content")
        self.form_widgets.extend([check, spin])
        self._footer(566, "创建容器", self._create_container)

    def _open_page(self) -> None:
        self._content_header(
            "OPEN CONTAINER",
            "打开容器",
            "正确密码导出真实 PDF；错误密码导出伪装 PDF，并记录错误次数。",
        )
        self._field("container", "安全容器", 238, "选择", self._choose_container)
        self._field("out", "导出 PDF", 294, "另存为", self._choose_open_out)
        self._password("password", "访问密码", 362)
        self._footer(446, "导出 PDF", self._open_container)

    def _password_page(self) -> None:
        self._content_header(
            "CHANGE PASSWORD",
            "修改密码",
            "用当前密码解锁后，生成一个使用新密码的新容器，也可以替换伪装 PDF。",
        )
        self._field("container", "安全容器", 212, "选择", self._choose_container)
        self._field("decoy", "替换伪装", 268, "可选", self._choose_decoy)
        self._field("out", "保存为", 324, "另存为", self._choose_password_out)
        self._password("current", "当前密码", 392)
        self._password("new", "新密码", 448)
        self._password("confirm", "确认密码", 504)
        self._footer(566, "更新密码", self._change_password)

    def _choose_real(self) -> None:
        path = filedialog.askopenfilename(title="选择真实 PDF", filetypes=[("PDF 文件", "*.pdf"), ("所有文件", "*")])
        if path:
            self.vars["real"].set(path)
            if not self.vars["out"].get():
                self.vars["out"].set(str(Path(path).with_suffix(".safe")))

    def _choose_decoy(self) -> None:
        path = filedialog.askopenfilename(title="选择伪装 PDF", filetypes=[("PDF 文件", "*.pdf"), ("所有文件", "*")])
        if path:
            self.vars["decoy"].set(path)

    def _choose_create_out(self) -> None:
        path = filedialog.asksaveasfilename(
            title="保存安全容器",
            defaultextension=".safe",
            filetypes=[("PDF-Protecter 容器", "*.safe"), ("所有文件", "*")],
        )
        if path:
            self.vars["out"].set(path)

    def _choose_container(self) -> None:
        path = filedialog.askopenfilename(
            title="选择安全容器",
            filetypes=[("PDF-Protecter 容器", "*.safe"), ("所有文件", "*")],
        )
        if path:
            self.vars["container"].set(path)
            if "out" in self.vars and not self.vars["out"].get():
                source = Path(path)
                suffix = ".pdf" if self.page == "open" else ".safe"
                name = source.with_suffix(suffix) if self.page == "open" else source.with_name(f"{source.stem}-updated.safe")
                self.vars["out"].set(str(name))

    def _choose_open_out(self) -> None:
        path = filedialog.asksaveasfilename(
            title="保存导出的 PDF",
            defaultextension=".pdf",
            filetypes=[("PDF 文件", "*.pdf"), ("所有文件", "*")],
        )
        if path:
            self.vars["out"].set(path)

    def _choose_password_out(self) -> None:
        path = filedialog.asksaveasfilename(
            title="保存更新后的容器",
            defaultextension=".safe",
            filetypes=[("PDF-Protecter 容器", "*.safe"), ("所有文件", "*")],
        )
        if path:
            self.vars["out"].set(path)

    def _create_container(self) -> None:
        try:
            if not self.vars["real"].get():
                raise PdfSafeError("请选择真实 PDF。")
            if not self.vars["decoy"].get():
                raise PdfSafeError("请选择伪装 PDF。")
            if not self.vars["out"].get():
                raise PdfSafeError("请选择保存位置。")
            if not self.vars["password"].get():
                raise PdfSafeError("请输入访问密码。")
            if self.vars["password"].get() != self.vars["confirm"].get():
                raise PdfSafeError("两次输入的密码不一致。")
            threshold = self.vars["destruct_after"].get() if self.vars["destruct"].get() else None
            create_container(
                Path(self.vars["real"].get()),
                Path(self.vars["decoy"].get()),
                Path(self.vars["out"].get()),
                self.vars["password"].get(),
                threshold,
            )
        except (PdfSafeError, OSError, ValueError) as exc:
            self.status.set("创建失败")
            messagebox.showerror("创建失败", str(exc), parent=self)
            return
        self.status.set(f"已创建：{self.vars['out'].get()}")
        messagebox.showinfo("创建完成", "安全容器已创建。", parent=self)

    def _open_container(self) -> None:
        try:
            if not self.vars["container"].get():
                raise PdfSafeError("请选择 .safe 安全容器。")
            if not self.vars["out"].get():
                raise PdfSafeError("请选择导出 PDF 的保存位置。")
            if not self.vars["password"].get():
                raise PdfSafeError("请输入访问密码。")
            result = open_container_status(
                Path(self.vars["container"].get()),
                Path(self.vars["out"].get()),
                self.vars["password"].get(),
            )
        except (PdfSafeError, OSError, ValueError) as exc:
            self.status.set("打开失败")
            messagebox.showerror("打开失败", str(exc), parent=self)
            return
        written = "真实 PDF" if result.real_was_written else "伪装 PDF"
        detail = f"已导出{written}。"
        if result.destroyed:
            detail += "\n容器内真实内容已经被销毁。"
        elif result.remaining_attempts is not None:
            detail += f"\n剩余错误尝试次数：{result.remaining_attempts}"
        self.status.set(f"已导出{written}：{self.vars['out'].get()}")
        messagebox.showinfo("导出完成", detail, parent=self)

    def _change_password(self) -> None:
        try:
            if not self.vars["container"].get():
                raise PdfSafeError("请选择 .safe 安全容器。")
            if not self.vars["out"].get():
                raise PdfSafeError("请选择保存位置。")
            if not self.vars["current"].get():
                raise PdfSafeError("请输入当前密码。")
            if not self.vars["new"].get():
                raise PdfSafeError("请输入新密码。")
            if self.vars["new"].get() != self.vars["confirm"].get():
                raise PdfSafeError("两次输入的新密码不一致。")
            decoy = Path(self.vars["decoy"].get()) if self.vars["decoy"].get() else None
            change_container_password(
                Path(self.vars["container"].get()),
                Path(self.vars["out"].get()),
                self.vars["current"].get(),
                self.vars["new"].get(),
                decoy,
            )
        except (PdfSafeError, OSError, ValueError) as exc:
            self.status.set("更新失败")
            messagebox.showerror("更新失败", str(exc), parent=self)
            return
        self.status.set(f"已更新：{self.vars['out'].get()}")
        messagebox.showinfo("更新完成", "安全容器密码已更新。", parent=self)


def main() -> int:
    app = PdfProtecterApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
