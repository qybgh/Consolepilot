# S2 · 渲染性能

验证 C6–C8：TextKit 方案、scrollback 批量裁剪、未闭合 Markdown 代码块回溯上色。

使用 50/200/500 token/s 压测，并在 Instruments 中记录 CPU、Hitches、内存和裁剪耗时。
