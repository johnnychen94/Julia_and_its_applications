# Julia 语言及其应用

[![CC BY-NC-SA 4.0][cc-by-nc-sa-image]][cc-by-nc-sa]

这是我在华东师范大学内部做的一个关于 Julia 的系列讲座时用到的材料， 主要目的是

- 介绍 Julia 这门语言
- 介绍一些科学计算中关于性能优化的一些基础知识
- 作为例子， 介绍一些我所了解领域中的基础知识， 例如： 数值计算、 图像处理、 机器学习和深度学习

如果关于材料的内容有疑问， 欢迎[开issue](https://github.com/johnnychen94/Julia_and_its_applications/issues/new)提问.

配置 Julia 请查看 [setup](setup.md)

## 时间及内容安排

**时间：** 2021年10月10日 - 2021年12月12日， 每周日下午 14:00 - 16:00

**地点：** 数学科学学院机房教室 200B

**内容大纲：**

已讲内容：

- （第一讲 10.10）： Julia 概述： 这是⼀⻔什么样的语⾔， 为什么要有这⻔语⾔， 以及当前的⽣态
- （第二讲 10.17）： Julia 的基本数据类型以及函数的定义
- （第三讲 10.24）： Julia 的类型系统和多重派发 （补充材料： 利用 functor 模式打造一个简单的深度学习方案）
- （第四讲 10.31）: [广播与向量化编程][4_1_broadcasting] （顺便演示了 [Julia-VSCode] 还有 [Revise.jl]）

待定：

- (11.7) 矩阵和迭代器接口， 并行计算简介
- (11.7， 11.14) CPU 并⾏计算： CPU 硬件模型、 SIMD、 多线程与异步模型、 多进程
- (11.21， 11.28) GPU 并⾏计算： GPU 硬件模型及 CUDA
- (12.5) 自动微分： 深度学习的核心组件
- (12.12) 待定

## 其他

- 原始仓库放在 [GitHub](https://github.com/johnnychen94/Julia_and_its_applications) 上面， 考虑到一些同学缺乏一些必要的技术手段， 在国内也镜像到 [Gitee](https://gitee.com/JohnnyChen94/julia_and_its_application)了。
- 致宏关于这些内容自己整理了一系列的笔记，有兴趣的话可以查看 [Rex's blog](https://www.wzhecnu.xyz/tags/Julia/) （2021年）

<!-- urls -->

[4_1_broadcasting]: https://johnnychen94.github.io/Julia_and_its_applications/4_1_broadcasting.jl.html
[Julia-VSCode]: https://www.julia-vscode.org/
[Revise.jl]: https://github.com/timholy/Revise.jl
[cc-by-nc-sa]: https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh
[cc-by-nc-sa-image]: https://mirrors.creativecommons.org/presskit/buttons/80x15/svg/by-nc-sa.svg
