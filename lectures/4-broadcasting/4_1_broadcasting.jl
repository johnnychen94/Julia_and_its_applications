### A Pluto.jl notebook ###
# v0.16.4

using Markdown
using InteractiveUtils

# ╔═╡ 8953d58d-d374-490e-a8f3-45c02c7c402b
using PlutoUI, BenchmarkTools, Plots, Images, TestImages, MLDatasets

# ╔═╡ 3c18930f-0d57-4f8e-ac75-7472ae3aa9d7
md"""
!!! tip "Pluto"
	[Pluto.jl](https://github.com/fonsp/Pluto.jl) 是 Julia 版本的 Jupyter. 这里面的内容是使用 Pluto 写的。
"""

# ╔═╡ 5b9352f6-79cd-447d-b838-435caad1fe61
md"""
# 广播和向量化代码

日期: 2021-10-31

作者： 陈久宁

大纲：

- 例： 绘制二维曲面
- 广播
- 向量化代码
- 总结

参考：

- [Julia Array Broadcasting](https://docs.julialang.org/en/v1/manual/arrays/#Broadcasting)
- [More Dots: Syntactic Loop Fusion in Julia](https://julialang.org/blog/2017/01/moredots/)
- [Numpy Broadcasting](https://numpy.org/doc/stable/user/basics.broadcasting.html)
"""

# ╔═╡ 1ed1f1cc-7fa8-4106-8e8b-42c796f69d26
md"""
## 例： 绘制二维曲面

绘制 `f(x,y) = x*exp(-x^2-y^2)` 网格曲面是一个典型的使用广播的例子

"""

# ╔═╡ 46fb0d31-0ed7-4843-8d87-0e514a9a816f
f(x, y) = x*exp(-x^2-y^2)

# ╔═╡ e50fe94b-1290-4915-ab12-21bb72cd1f80
md"""
简单来说， 为了绘制上面的这种二维曲面， 我们需要

1) 确定绘制的格点坐标 (x, y)
2) 确定每个格点上的函数值 f(x, y)

因此最直接的办法就是用 for 循环来做这件事情， 即：
"""

# ╔═╡ 5beb84ea-7c2e-425d-ae5e-f094a69a2236
begin
	X = -2:0.1:2
	Y = -2:0.1:2

	Z = zeros(size(X)..., size(Y)...)

	for i in axes(X, 1), j in axes(Y, 1)
		Z[i,j] = f(X[i], Y[j])
	end

	surface(Z)
end

# ╔═╡ 9bfb324d-d2d9-444b-87c3-d8bd3f720bf3
md"""
这样做唯一的问题在于代码变得非常冗长： 你需要 6 行甚至更多行代码来实现简单的格点计算。如果你是 MATLAB 用户的话， 你受过的教育也许会告诉你应该像下面这样通过 meshgrid 来高效地实现这一目的：

```matlab
% matlab code
X = -2:0.2:2;
Y = -2:0.2:2;

[X, Y] = meshgrid(X, Y);
Z = X .* exp(-X.^2-Y.^2);

surf(X, Y, Z)
```

Python 用户也可以在 numpy 下找到同样的 `meshgrid`， 似乎这就已经足够了。 告诉你 `meshgrid` 函数的人也许也会告诉你用 `meshgrid` 的效率非常高。

但最主要的问题是：

- 为什么要用 `meshgrid` 以及如何理解 `meshgrid` 的输出慢慢地成为了一个谜团
- `meshgrid` 所谓的效率高实际上是一个性能上的取舍 (tradeoff)

为了说明这个问题， 让我们在 Julia 下来实现一个简单的 `meshgrid` 函数：
"""

# ╔═╡ 600106f0-9f85-443a-b118-958ba9114f36
function meshgrid(X, Y)
	# 实际上利用 map 或者循环也很容易地可以写成支持任意输入的形式
	# 不妨作为练习尝试一下 meshgrid(Xs...) 的实现
	X̂ = repeat(reshape(X, :, 1), 1,         length(Y))
	Ŷ = repeat(reshape(Y, 1, :), length(X), 1        )
	return X̂, Ŷ
end

# ╔═╡ 17979516-8b02-47a0-918e-f971745bd745
begin
	X1 = [1, 2]
	Y1 = [3, 4, 5]
	X1, Y1 = meshgrid(X1, Y1)
end

# ╔═╡ b693b8b5-3672-47b1-ace9-86e67ade269d
md"""
实际上， `meshgrid` 的目的是为了将尺寸并不相同的向量 `X`， `Y` 构造成尺寸相同的版本 `X̂`, `Ŷ` 并且保证下面两个 for 循环是等价的：

```julia
for i in axes(X, 1), j in axes(X, 2)
	Z[i, j] = f(X[i, j], Y[i, j])
end

for i in axes(X, 1), j in axes(Y, 1)
	Z[i, j] = f(X[i], Y[j])
end
```

这样做的好处是: 在循环的时候 `X` 与 `Y` 的下标是一致的， 从而可以以向量化地形式调用函数 `f`. MATLAB 或者 numpy 下的 `f(X, Y)` 在 Julia 下等价的形式是：
"""

# ╔═╡ 309034d6-9c1c-4e15-af99-c976481af9ec
# 不妨尝试一下 f(X1, Y1) 看看会发生什么 :)
f.(X1, Y1)

# ╔═╡ af11fa72-782e-4480-a13b-24583749b81b
md"""
由点号 `.` 触发的运算我们称为广播 (Broadcasting)。 对于 `f.(X, Y)` 来说， 当 `X` 与 `Y` 的尺寸一致时, 以下两个运算是等价的：

```julia
Z = f.(X, Y)

for i in axes(X, 1), j in axes(X, 2)
    Z[i, j] = f(X[i, j], Y[i, j])
end
```

因此， 当我们进行广播运算时， `f` 实际上被调用了很多次， 并且每次调用的实际输入是一个标量。
"""

# ╔═╡ 04436d60-fd1f-42ff-8921-19f066f36ef9
with_terminal() do
	foo(x) = @show typeof(x) x
	@info "直接调用"
	foo(1)
	foo([1, 2])
	@info "通过广播调用"
	foo.([1, 2]);
end

# ╔═╡ b795d6e3-64bc-4edc-a65e-aa76e8d79938
md"""
让我们做一个简单的性能测试看看：
"""

# ╔═╡ a5d52ac9-3afd-432b-ba18-ad40a43bd8f2
begin
	f_broadcast(X, Y) = f.(X, Y)

	function f_loop(X, Y)
		@assert axes(X) == axes(Y)
		Z = similar(X)
		@inbounds @simd for i in CartesianIndices(X)
			# @inbounds 避免了取下标 X[i] 时进行的下标越界检查
			# @simd 用来允许 CPU 级别的并行计算
			Z[i] = f(X[i], Y[i])
		end
		return Z
	end
end

# ╔═╡ b799a4de-5cca-46db-8654-7423d24d453f
with_terminal() do
	@assert f_loop(X, Y) == f_broadcast(X, Y)

	@btime f_broadcast($X, $Y);
	@btime f_loop($X, $Y);
	nothing
end

# ╔═╡ 9c4dd774-13cf-4dad-a2ce-b890e6cae4ee
md"""
值得一提的是， 这样一件看起来很简单事情在 MATLAB 或者 Python 下并不简单： 因为这些动态语言的 for 循环是非常缓慢的。 所以如果你试图去检查调用次数的话， 你会发现下面这个函数在 MATLAB 或者 Python 下只会调用一次：

```matlab
% matlab code
function Z = f(X, Y)
    print("Called once")
    Z = X .* exp(-X.^2-Y.^2);
    return
end
```

这是因为实际的 for 循环发生在 C 的那一部分代码了。 也就是说， 当你试图去执行 `X .* Y` 这样一个看似简单的操作时， 在 C 那边进行了类似于刚才我们用 Julia 写的 for 循环。 这样做的好处是可以避免在 MATLAB/Python 端执行低效的 for 循环从而加速代码执行。

!!! note "广播的历史"
	广播 `.` 这一符号的引入让这件事情变得非常简洁且易读： 毕竟没有人会享受用 `broadcast(*, X, Y)` 这样的方式来表达 `X .* Y` 这样基本的数学运算。 这也是为什么 MATLAB `bsxfun` 和 Python `np.dot` 退出历史舞台的原因。

让我们先总结一下：

- MATLAB/Python 这些动态语言的 for 循环非常缓慢
- C/C++/Fortran 这些编译型语言的 for 循环非常高效
- 广播运算允许我们将 for 循环的执行从一门缓慢的语言转移到一门高效的语言上执行

!!! warning "广播不是银弹"
	广播并没有消除 for 循环， 它只是将 for 循环转移到了更底层的 C/Fortran 代码上。 如果有一天你发现一个你急需的功能没有现成的 C 代码进行支撑的时候， 你就得亲手去写它了。 那会是非常有趣（或痛苦）的一次经历。
"""

# ╔═╡ 14a173eb-fd20-4e98-a32a-263f70fb6f14
md"""
回到我们绘制二维曲面的例子， 一旦你理解了广播的规则， 你会立刻发现实际上我们可以这样做:
"""

# ╔═╡ 6fc60f63-e6cc-4596-b924-fee0ae733fda
surface(f.(X, Y'))

# ╔═╡ 86084173-0b89-433e-97a3-ee70706233e7
md"""
!!! tip "函数式编程!"
	实际上对于绘制曲面这一问题而言， Plots 支持更简洁和易理解的写法 `surface(X, Y, f)`
"""

# ╔═╡ 9c7eaa4d-da57-4110-89b8-270aa74e1605
md"""
## 广播的规则

对于 Julia 来说， 因为存在高效的 for 循环， 所以即使不用广播也并不会让代码变得更慢， 但是使用广播的话则可以让代码变得更佳简洁易读。

关于广播， 我们的第一条规则就是：

1. 当 `X` 与 `Y` 尺寸一致时， 可以使用广播。 此时 `f.(X, Y)` 等价于 `map(f, X, Y)` 或者更长的 for 循环。
"""

# ╔═╡ 57f5be0e-381a-4323-8322-1b9d5b1005de
g(x, y) = x + y

# ╔═╡ 903fd282-8621-48a7-bfed-0c8bcdc70f41
g.([1, 2], [3, 4])

# ╔═╡ f5cdb1b0-8a0b-42ec-aaa2-89948d027ff5
md"""
除此之外， 广播同样也允许一些不同尺寸的情况：

2. 当 `X` 与 `Y` 的维数一致时， 并且尺寸不相同的维度上， 其中一个的长度为 1. 此时长度为 1 的那个维度会被复制到尺寸一致.
"""

# ╔═╡ 37913c90-1066-44e8-91ce-d7f5abdd4dc1
begin
	x1 = [1 2 3; 4 5 6] # 2x3
	y1 = reshape([5, 6], 2, 1) # 2x1
	g.(x1, y1) # 2x3
	# 等价于
	# g.(x1, repeat(y1, 1, 3))
end

# ╔═╡ 424e1143-aebc-4d5b-ba92-569258c61757
begin
	x2 = [1 2 3; 4 5 6] # 2x3
	y2 = [5 6 7] # 1x3
	g.(x2, y2) # 2x3
	# 等价于
	# g.(x2, repeat(y2, 2, 1))
end

# ╔═╡ 21ad8c6e-d500-4b55-b21a-02395552a8b0
md"""
长度为1的维度相互交叉也是允许的：
"""

# ╔═╡ a38ef901-bcca-4b07-9be5-09dfb03ea976
begin
	x3 = reshape([1, 2, 3], 3, 1) # 3x1
	y3 = reshape([5, 6], 1, 2) # 1x2
	g.(x3, y3) # 3x2
	# 等价于
	# g.(repeat(x3, 1, 2), repeat(y3, 3, 1))
end

# ╔═╡ db59f087-3ddd-46a4-8c17-3acb6219c60b
md"""
!!! note "Repeat 有多种展开模式"
	之所以我们要求广播在尺寸不同的维度上长度必须为 `1` 的原因是， `repeat` 的展开模式是有可能有歧义的。 只有当长度为 `1` 的时候， 展开的方式才是唯一的。
"""

# ╔═╡ e24b29d3-5fd8-4242-81ac-174c62509f6a
with_terminal() do
	@show repeat([1, 2, 3], inner=3)
	@show repeat([1, 2, 3], outer=3)
	nothing
end

# ╔═╡ d1eb882b-8460-4f58-9ffa-23b224ae9cd3
md"""
关于广播的第三条规则是：

3. 当 `X` 与 `Y` 的维数不一致时， 将维数较短的矩阵的尾部添加一系列的长度为 1 的维度后， 再回到第二条规则。

!!! note "Trailing dimension"
	这种放在尾部且不改变实际内存结构的维度一般称为 trailing dimensions.
"""

# ╔═╡ 8dec6c6d-209c-4a9e-ab97-9f7283417aa4
begin
	x4 = reshape([1 2 3; 4 5 6], 3, 2) # 3x2
	y4 = [7, 8, 9] # 3 ---> 3x1

	g.(x4, y4) # 3x2
end

# ╔═╡ e628d4dc-8f15-4909-a434-60b596585dd2
md"""
现在我们知道 `meshgrid` 只是将广播的规则手动实现了一遍而已。 换句话说， 在现代语言框架都已经广泛支持广播的情况下， 大多数时候并不需要手动调用 `meshgrid` 函数。
"""

# ╔═╡ 8f199bf9-c27d-4d5e-ae50-bfee13b01587
md"""

## Reshape and Permute

当 `X` 和 `Y` 的尺寸并不符合广播的上述三条规则时， 则需要手动通过 `reshape` 或者 `permutedims` 调整维度。 具体使用哪一种需要根据实际情况来进行决定：

- `reshape`: 在不改变内存顺序的情况下调整尺寸
- `permutedims`: 交换维度 （同时会改变内存顺序）

!!! note "Row- and Column-major order"
	多维数组在内存中的存储方式有两种： 按行存储与按列存储。 Julia, MATLAB, Fortran 使用按列存储， C/C++ 使用按行存储。 Numpy 默认使用按行存储。 [Wiki Page](https://en.wikipedia.org/wiki/Row-_and_column-major_order)
"""

# ╔═╡ 30034666-8f93-41b8-9c08-a9f8ed9d70bf
md"""
!!! note "Locality"
	不同的 for 循环写法会导致不同的代码性能。 参考 [Wiki: Locality of reference](https://en.wikipedia.org/wiki/Locality_of_reference)
"""

# ╔═╡ cc3447af-ed5b-426e-98d4-5213ac564390
begin
	function my_sum_v1(X)
		rst = zero(eltype(X))
		@inbounds for i in axes(X, 1)
			@simd for j in axes(X, 2)
				rst += X[i, j]
			end
		end
		return rst
	end

	function my_sum_v2(X)
		rst = zero(eltype(X))
		@inbounds for j in axes(X, 2)
			@simd for i in axes(X, 1)
				rst += X[i, j]
			end
		end
		return rst
	end
end

# ╔═╡ ade6d569-36bf-4b67-9671-7426cd079119
with_terminal() do
	X = rand(101, 101)

	@btime my_sum_v1($X)
	@btime my_sum_v2($X)
	nothing
end

# ╔═╡ 3d7b8ed3-b3f2-4e1e-8075-c10e74807e58
md"""
小练习： 通过 for 循环来展开计算矩阵乘法 A * B. 哪种展开最高效？
"""

# ╔═╡ 7f4142b8-6c19-4c03-b7bc-ab1639d1991a
with_terminal() do
	x5 = [1, 2, 3, 4, 5, 6]
	y5 = reshape(x5, 2, 3)
	z5 = reshape(x5, 6)
	@show axes(x5) axes(y5) axes(z5)
	# 将数据拉成一列之后发现是相同的， 也就是说 reshape 不改变内存排列
	@show x5[:] y5[:] z5[:]
	nothing
end

# ╔═╡ 9b4389ac-e5b3-4634-aa12-860f6b581114
md"""
`permutedims` 是矩阵转置的一般版本， 它基于代数变换的规则进行设计， 例如：

`Y = permutedims(X, (i, j, k))` 构造的是下述维度轮换：

|            |     |     |     |
| ---        | --- | --- | --- |
| X 维度      | 1   |  2  |  3  |
| Y 维度      | i   |  j  |  k  |

因此， 对应的维度应该具有相同的尺寸， 例如： `axes(X, 1) == axes(Y, i)`. 如果想要将 `Y` 转换回去的话， 需要使用该轮换的逆轮换.

"""

# ╔═╡ e7417c94-5688-4c43-8078-5d0641cf7881
with_terminal() do
	x6 = reshape(1:12, 2, 3, 2)
	y6 = permutedims(x6, (3, 1, 2))
	z6 = permutedims(y6, invperm((3, 1, 2))) # 即 (2, 3, 1)
	@show axes(x6) axes(y6) axes(z6)
	# x6 与 y6 的内存顺序是不相同的
	@show x6[:] y6[:] z6[:]
	nothing
end

# ╔═╡ dfc822fd-1b38-495e-b9b1-6938064b46ca
md"""
## 向量化编程

所谓向量化编程就是尽可能避免显式 for 循环的代码。 这背后的逻辑是为了尽可能将 for 循环从低效的 Python/MATLAB 端转移到高效的 C/Fortran 端， 从而尽可能少地触发这些动态语言的性能瓶颈。 例如， [MATLAB 的官方手册](https://ww2.mathworks.cn/help/matlab/matlab_prog/techniques-for-improving-performance.html?lang=en) 上就将向量化代码作为一个好的性能优化手段进行推荐。

因为在其他语言中并不允许直接对函数进行广播操作， 所以派生出了向量化函数的概念， 即采用与广播相同规则的函数。 简单来说， 我们称

- `f(x::Real, y::Real) = x * y` 为标量函数
- `f(X::AbstractArray, Y::AbstractArray) = X .* Y` 为向量化函数

但是向量化代码有以下几个问题：

- 向量化代码的实现需要底层 C/Fortran 代码进行支撑。 如果你所关心的问题恰好没有人在 C/Fortran 下给出高效实现的话， 那么就需要你自己来做了。 或者如果恰好底层代码存在 bug 而你恰好没有足够的知识储备来修复的话， 那就只能 🙏 了。
- 向量化代码的中间结果是数组而非标量， 因此会带来一定的额外内存开销。
- 向量化代码的代码逻辑分散在高效的 C/Fortran 端和低效的 Python/MATLAB， 因此阻碍了一些本可以进行的性能优化， 并且也带来了一些不必要的代码。
- 相比于标量代码来说， 向量化代码既不容易阅读， 也不容易写对。

!!! note "结论"
	向量化代码并不意味着着一定是“好的”代码， 它是在特定语言和平台下关于性能、易用性和可维护性的一个技术选择和取舍。
"""

# ╔═╡ a9ae6884-4af4-43de-8b4f-421f8ba932ef
md"""

关于向量化代码的中间结果是数组而非标量这件事情， 这里用一个非常简单的例子来说明它： `muladd` 是一个非常底层的数值运算， 在数学上其标量版本为 `muladd(a, b, c) = a * b + c`。 这个运算有两种可能的实现方式：
"""

# ╔═╡ 6e84af17-3154-49e1-8fe2-03f5301ebe63
begin
	# Version 1: 向量化代码
	# 问： 如果写 `A .* B .+ C` 时会发生什么?
	muladd_vec(A::AbstractArray, B, C) = A .* B + C

	# Version 2: 对标量函数整体进行广播
	_muladd(a::Number, b, c) = a * b + c
	# 问： 下面这个运算等价的 for 循环形式如何写？
	muladd_broadcast(A::AbstractArray, B, C) = _muladd.(A, B, C)
end


# ╔═╡ 7488e45e-e35b-43e6-be74-d86e958ac265
with_terminal() do
	MA, MB, MC = rand(101, 101), rand(101, 101), rand(101, 101)
	@btime muladd_vec($MA, $MB, $MC);
	@btime muladd_broadcast($MA, $MB, $MC);
	nothing
end

# ╔═╡ 01ef7470-e3a9-4007-931f-63ffc59eec9b
md"""
我们发现第一个版本`muladd_vec`更慢一些， 并且在内存分配上有4次内存创建的过程。 这是因为

```julia
A .* B + C
```

等价于

```julia
tmp = A .* B
tmp + C
```

因此额外地分配了一段内存给 `tmp`.

!!! note "向量化代码的中间结果是数组而非标量"
	向量化代码的所有中间结果都需要使用向量进行存储， 对于底层运算来说， 内存分配经常会是性能的瓶颈。 在 MATLAB/Numpy 中， 一旦内存分配构成明显的性能瓶颈的时候， 这部分代码就必须用 C 重写成循环的版本。
"""

# ╔═╡ 0ba41c20-42fb-40d5-a57a-e065bc6b511d
md"""
### Fused dots

`A .* B .+ C` 这种运算非常普遍， 它背后有两种可能的实现方式：

```julia
tmp = A .* B
tmp .+ C
```

或

```julia
f(a, b, c) = a * b + c
f.(A, B, C)
```

我们现在知道， 第二种实现方式可以避免中间存储是矩阵的不必要内存开销， 因此 Julia 提供了一个内置的 fused dots 机制， 即： 只要整个运算都是点运算那么 Julia 就会试图构造一个这样的一个标量形式的函数， 然后对函数整体进行广播。 同时， Julia 也提供了一个 `@.` 宏用来辅助代码书写
"""

# ╔═╡ 05935ff1-f5c3-4735-93d4-9a382b921047
begin
	muladd_v1(A, B, C) = A .* B + C
	# 以下两种写法是完全等价的 （不妨使用 `@macroexpand` 验证一下）
	muladd_v2(A, B, C) = A .* B .+ C
	muladd_v3(A, B, C) = @. A * B + C
end

# ╔═╡ f185f8bf-6cc7-4802-af85-4262315115e9
with_terminal() do
	MA, MB, MC = rand(101, 101), rand(101, 101), rand(101, 101)
	@btime muladd_v1($MA, $MB, $MC);
	@btime muladd_v2($MA, $MB, $MC);
	@btime muladd_v3($MA, $MB, $MC);
	nothing
end

# ╔═╡ 3374b574-13c3-4249-bc22-4ccd1666330c
@macroexpand @. X * X + X # 等价于 X .* X .+ X

# ╔═╡ de3f02d7-7718-4c23-aa1f-a1d7d34d8561
md"""
关于 Fused dots 和广播， 非常建议继续阅读：

- [Dot Syntax for Vectorizing Functions](https://docs.julialang.org/en/v1/manual/functions/#man-vectorized)
- [More Dots: Syntactic Loop Fusion in Julia](https://julialang.org/blog/2017/01/moredots/)
"""

# ╔═╡ d13dd463-2b26-4b6c-bd0f-8300db6bef2b
md"""
### view 和 copy

不必要的内存开销一直都是性能优化致力于解决的问题。 我们经常会遇到类似于下面的代码：
"""

# ╔═╡ 54d95539-6756-46a7-9677-04d97f1d7e43
Zx = X[1:4].^2

# ╔═╡ 21548a8d-eda7-4701-95c6-93c983578889
md"""
这里 `X[1:4]` 实际上是以只读的方式在工作的， 它的值并没有被修改。 因此我们也没有必要为此创建额外的内存。
"""

# ╔═╡ f97da5d3-dcec-454c-b1ed-0522972e140c
md"""
很自然地就有了 view 模式， 即： 取下标的时候只是对原始内存进行一个重新标记， 并不创建新的内存空间。
"""

# ╔═╡ 7bb39eb0-47ac-4b44-b235-ef5b6afff9f1
with_terminal() do
	println("Copy mode:")
	X = [1, 2, 3, 4]
	Y = X[1:4]
	Y[1] = 0
	@show X Y

	println("View mode:")
	X = [1, 2, 3, 4]
	Y = @view X[1:4]
	Y[1] = 0
	@show X Y

	nothing
end

# ╔═╡ 7887a628-e05f-48f1-8f9d-9ea58264f65e
md"""
!!! tip "@view 和 @views"
	Julia 默认情况下是对数组进行索引时是会进行复制的， 因此修改 `Y` 的值并不会改变 `X`。 如果索引是只读的情形， 我们就可以利用 `@view` 这个宏进行标记， 从而避免内存开销。 当然也有很多情况下我们会使用 `@view` 来共享数据。 类似的还有 `@views` 宏用来标记整个函数段。

!!! info "MATLAB/Numpy"
	Numpy 默认[使用 view 进行索引](https://numpy.org/doc/stable/reference/arrays.indexing.html)， 而 MATLAB 则采用（听起来）更酷炫的 [Copy-On-Write](https://www.mathworks.com/help/matlab/matlab_prog/avoid-unnecessary-copies-of-data.html) 技术.
"""

# ╔═╡ 1bc0bb7a-1dd2-4ed9-a2e0-9791c8d43f3e
md"""
### 例： MNIST 数据集
"""

# ╔═╡ 37cb53d6-85b9-4782-8c2d-bffda2687338
md"""
在处理数据的时候， 经常会需要对整个数据集进行一些初步的预处理和分析。 例如， 对于 [MNIST 手写数字数据集](http://yann.lecun.com/exdb/mnist/)来说， 我们可能会想要知道每一个类别的一个平均图像, 例如： 所有标签为 1 的图像的平均值。
"""

# ╔═╡ 15a050bd-4190-4bd2-b976-88fc1b48ce2a
begin
	# 10000 张 28x28 的灰度图片
	mnist_imgs, mnist_labels = MNIST.testdata()

	# 原始数据是按行存储的， 因此在 Julia 中进行以下行与列的交换使得图像以正常方向显示
	mnist_imgs = permutedims(mnist_imgs, (2, 1, 3))

	# 预览一下整个数据集； `mosaic` 可以将多张图片融合成一张单图方便显示
	mosaic(Gray.(mnist_imgs[:, :, 1:64]), nrow=8)
end

# ╔═╡ 197cc773-8b68-458b-a32b-7b506eabca38
md"""
处理数据的时候为了统一数值， 经常会遇到需要做归一化 (normalization) 的情况， 例如， 下述变换将数据转换到 $[-0.5, 0.5]$ 的范围内

```math
f(X) = (X - min(X))/(max(X) - min(X)) - 0.5
```
"""

# ╔═╡ 35c0ad63-c3fc-4f1b-b852-b0d2db49e953
begin
	mnist_imgs # 28x28x10000
	mx = maximum(mnist_imgs, dims=(1, 2)) # 1x1x10000
	mn = minimum(mnist_imgs, dims=(1, 2)) # 1x1x10000
	mnist_imgs_scaled = @. (mnist_imgs - mn)/(mx - mn) - 0.5
	mosaic(
		Gray.(mnist_imgs_scaled[:, :, 1:64]),
		Gray.(mnist_imgs[:, :, 1:64]);
		nrow=8
	)
end

# ╔═╡ 35e7502b-f3e0-4377-9ed7-a04bb7c1d423
md"""
看起来不错。 不过这是效率最高的方法吗？
"""

# ╔═╡ db592332-5bde-47af-9609-ab41b3b47027
begin
	function normalize_v1(imgs)
		mx = maximum(imgs, dims=(1, 2))
		mn = minimum(imgs, dims=(1, 2))
		return @. (imgs - mn)/(mx - mn) - 0.5
	end

	function normalize_v2(imgs)
		out = similar(imgs)
		mx = maximum(imgs, dims=(1, 2))
		mn = minimum(imgs, dims=(1, 2))
		@inbounds for i in axes(imgs, 3)
			v = @view imgs[:, :, i]
			@. out[:, :, i] = (v - mn[i])/(mx[i] - mn[i]) - 0.5
		end
		return out
	end
end

# ╔═╡ f108fbfa-a3c0-4e3a-8a5a-c03b43ba9805
with_terminal() do
	imgs = float64.(mnist_imgs[:,:,1:64])
	@btime normalize_v1($imgs)
	@btime normalize_v2($imgs)
	nothing
end

# ╔═╡ f50d4326-55e4-47cb-88b8-32ba882965cf
md"""
问： 为什么第二种实现要比第一种快？ 这里是因为第二个版本的代码中每个 for 循环里的广播中只有第一项是数组， 因此可以触发更高效的循环和广播展开。

!!! note
	广播并不是万能的， 有些时候依然需要手写 for 循环来辅助广播机制， 从而达到更高效的缓存利用率。 当然这件事情对于 MATLAB/Python 来说是不一定存在的， 因为在这些语言里展开成 for 循环本身可能会引入更多的开销。
"""

# ╔═╡ c02e901e-e52f-4d41-a9d1-6e7041b3fe3e
md"""
## 总结

在这里我们介绍了以下一些概念：

- 广播： 本质上是 for 循环的一个抽象。 在动态语言中经常被拿来作为将 for 循环转移到 C/Fortran 的手段。
- 向量化编程： 将广播进行到底
- View vs Copy： 在能使用 View 的时候使用 View 来节省内存

我们说向量化编程仅仅只是一个技术选型， 并不永远是最好的方案。 在 Julia 中大部分时候并不鼓励向量化编程， 而是鼓励写标量函数， 然后通过广播的形式组合起来。


!!! note "向量化编程作为并行计算的手段"
	我们说向量化代码的目的是为了绕过动态解释型语言的 for 循环导致的性能瓶颈。 但是对于 Julia （或者其他不存在 for 循环瓶颈） 的语言来说， 是否就意味着向量化没有必要了呢？ 实际上， 向量化代码存在一个很有用的场景： 并行计算。 当代码逻辑不包含显式 for 循环的时候， 底层 for 循环的执行顺序就可以由底层代码进行任意调整。 这意味着一旦底层代码支持 CPU/GPU 的并行计算， 那么高层的向量化代码也会立刻能够支持。

	这一点对于 CUDA 编程极其重要： 由于 GPU 设备的硬件设计原因， 对 GPU 上的矩阵进行取单个下标的效率是非常低的， 必须要批量操作才能够达到比较高的效率。 因此 GPU 代码的高效实现目前只有两种模式： 1) 用 C/C++ 手搓 CUDA kernel 以及 2) 通过向量化编程来调用已有的 CUDA kernel。 其中向量化编程相比于手搓 CUDA 来说的学习成本则要要低得多， 并且适用的场景也更多。
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
Images = "916415d5-f1e6-5110-898d-aaa5f9f070e0"
MLDatasets = "eb30cadb-4394-5ae3-aed4-317e484a6458"
Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
TestImages = "5e47fb64-e119-507b-a336-dd2b206d9990"

[compat]
BenchmarkTools = "~1.2.0"
Images = "~0.24.1"
MLDatasets = "~0.5.12"
Plots = "~1.23.1"
PlutoUI = "~0.7.16"
TestImages = "~1.6.2"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.7.0-rc2"
manifest_format = "2.0"

[[deps.AbstractFFTs]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "485ee0867925449198280d4af84bdb46a2a404d0"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.0.1"

[[deps.Adapt]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "84918055d15b3114ede17ac6a7182f68870c16f7"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.3.1"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[deps.ArrayInterface]]
deps = ["Compat", "IfElse", "LinearAlgebra", "Requires", "SparseArrays", "Static"]
git-tree-sha1 = "a8101545d6b15ff1ebc927e877e28b0ab4bc4f16"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "3.1.36"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.AxisAlgorithms]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "WoodburyMatrices"]
git-tree-sha1 = "66771c8d21c8ff5e3a93379480a2307ac36863f7"
uuid = "13072b0f-2c55-5437-9ae7-d433b7a33950"
version = "1.0.1"

[[deps.AxisArrays]]
deps = ["Dates", "IntervalSets", "IterTools", "RangeArrays"]
git-tree-sha1 = "d127d5e4d86c7680b20c35d40b503c74b9a39b5e"
uuid = "39de3d68-74b9-583c-8d2d-e117c070f3a9"
version = "0.4.4"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "61adeb0823084487000600ef8b1c00cc2474cd47"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.2.0"

[[deps.BinDeps]]
deps = ["Libdl", "Pkg", "SHA", "URIParser", "Unicode"]
git-tree-sha1 = "1289b57e8cf019aede076edab0587eb9644175bd"
uuid = "9e28174c-4ba2-5203-b857-d8d62c4213ee"
version = "1.0.2"

[[deps.BinaryProvider]]
deps = ["Libdl", "Logging", "SHA"]
git-tree-sha1 = "ecdec412a9abc8db54c0efc5548c64dfce072058"
uuid = "b99e7846-7c00-51b0-8f62-c81ae34c0232"
version = "0.5.10"

[[deps.Blosc]]
deps = ["Blosc_jll"]
git-tree-sha1 = "84cf7d0f8fd46ca6f1b3e0305b4b4a37afe50fd6"
uuid = "a74b3585-a348-5f62-a45c-50e91977d574"
version = "0.7.0"

[[deps.Blosc_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Lz4_jll", "Pkg", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "e747dac84f39c62aff6956651ec359686490134e"
uuid = "0b7ba130-8d10-5ba8-a3d6-c5182647fed9"
version = "1.21.0+0"

[[deps.BufferedStreams]]
deps = ["Compat", "Test"]
git-tree-sha1 = "5d55b9486590fdda5905c275bb21ce1f0754020f"
uuid = "e1450e63-4bb3-523b-b2a4-4ffa8c0fd77d"
version = "1.0.0"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[deps.CEnum]]
git-tree-sha1 = "215a9aa4a1f23fbd05b92769fdd62559488d70e9"
uuid = "fa961155-64e5-5f13-b03f-caf6b980ea82"
version = "0.4.1"

[[deps.Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "LZO_jll", "Libdl", "Pixman_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "f2202b55d816427cd385a9a4f3ffb226bee80f99"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.16.1+0"

[[deps.CatIndices]]
deps = ["CustomUnitRanges", "OffsetArrays"]
git-tree-sha1 = "a0f80a09780eed9b1d106a1bf62041c2efc995bc"
uuid = "aafaddc9-749c-510e-ac4f-586e18779b91"
version = "0.2.2"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "3533f5a691e60601fe60c90d8bc47a27aa2907ec"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.11.0"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[deps.ColorSchemes]]
deps = ["ColorTypes", "Colors", "FixedPointNumbers", "Random"]
git-tree-sha1 = "a851fec56cb73cfdf43762999ec72eff5b86882a"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.15.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "024fe24d83e4a5bf5fc80501a314ce0d1aa35597"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.0"

[[deps.ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "SpecialFunctions", "Statistics", "TensorCore"]
git-tree-sha1 = "45efb332df2e86f2cb2e992239b6267d97c9e0b6"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.9.7"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "417b0ed7b8b838aa6ca0a87aadf1bb9eb111ce40"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.8"

[[deps.Compat]]
deps = ["Base64", "Dates", "DelimitedFiles", "Distributed", "InteractiveUtils", "LibGit2", "Libdl", "LinearAlgebra", "Markdown", "Mmap", "Pkg", "Printf", "REPL", "Random", "SHA", "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics", "Test", "UUIDs", "Unicode"]
git-tree-sha1 = "31d0151f5716b655421d9d75b7fa74cc4e744df2"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "3.39.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[deps.ComputationalResources]]
git-tree-sha1 = "52cb3ec90e8a8bea0e62e275ba577ad0f74821f7"
uuid = "ed09eef8-17a6-5b46-8889-db040fac31e3"
version = "0.3.2"

[[deps.Conda]]
deps = ["JSON", "VersionParsing"]
git-tree-sha1 = "299304989a5e6473d985212c28928899c74e9421"
uuid = "8f4d0f93-b110-5947-807f-2305c1781a2d"
version = "1.5.2"

[[deps.Contour]]
deps = ["StaticArrays"]
git-tree-sha1 = "9f02045d934dc030edad45944ea80dbd1f0ebea7"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.5.7"

[[deps.CoordinateTransformations]]
deps = ["LinearAlgebra", "StaticArrays"]
git-tree-sha1 = "6d1c23e740a586955645500bbec662476204a52c"
uuid = "150eb455-5306-5404-9cee-2592286d6298"
version = "0.6.1"

[[deps.CustomUnitRanges]]
git-tree-sha1 = "1a3f97f907e6dd8983b744d2642651bb162a3f7a"
uuid = "dc8bdbbb-1ca9-579f-8c36-e416f6a65cce"
version = "1.0.2"

[[deps.DataAPI]]
git-tree-sha1 = "cc70b17275652eb47bc9e5f81635981f13cea5c8"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.9.0"

[[deps.DataDeps]]
deps = ["BinaryProvider", "HTTP", "Libdl", "Reexport", "SHA", "p7zip_jll"]
git-tree-sha1 = "4f0e41ff461d42cfc62ff0de4f1cd44c6e6b3771"
uuid = "124859b0-ceae-595e-8997-d05f6a7a8dfe"
version = "0.7.7"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "7d9d316f04214f7efdbb6398d545446e246eff02"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.10"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[deps.Distances]]
deps = ["LinearAlgebra", "Statistics", "StatsAPI"]
git-tree-sha1 = "09d9eaef9ef719d2cd5d928a191dc95be2ec8059"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.5"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "b19534d1895d702889b219c382a6e18010797f0b"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.8.6"

[[deps.Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[deps.EarCut_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3f3a2501fa7236e9b911e0f7a588c657e822bb6d"
uuid = "5ae413db-bbd1-5e63-b57d-d24a61df00f5"
version = "2.2.3+0"

[[deps.EllipsisNotation]]
deps = ["ArrayInterface"]
git-tree-sha1 = "8041575f021cba5a099a456b4163c9a08b566a02"
uuid = "da5c29d0-fa7d-589e-88eb-ea29b0a81949"
version = "1.1.0"

[[deps.Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b3bfd02e98aedfa5cf885665493c5598c350cd2f"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.2.10+0"

[[deps.FFMPEG]]
deps = ["FFMPEG_jll"]
git-tree-sha1 = "b57e3acbe22f8484b4b5ff66a7499717fe1a9cc8"
uuid = "c87230d0-a227-11e9-1b43-d7ebe4e7570a"
version = "0.4.1"

[[deps.FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "Pkg", "Zlib_jll", "libass_jll", "libfdk_aac_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "d8a578692e3077ac998b50c0217dfd67f21d1e5f"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "4.4.0+0"

[[deps.FFTViews]]
deps = ["CustomUnitRanges", "FFTW"]
git-tree-sha1 = "cbdf14d1e8c7c8aacbe8b19862e0179fd08321c2"
uuid = "4f61f5a4-77b1-5117-aa51-3ab5ef4ef0cd"
version = "0.3.2"

[[deps.FFTW]]
deps = ["AbstractFFTs", "FFTW_jll", "LinearAlgebra", "MKL_jll", "Preferences", "Reexport"]
git-tree-sha1 = "463cb335fa22c4ebacfd1faba5fde14edb80d96c"
uuid = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
version = "1.4.5"

[[deps.FFTW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c6033cc3892d0ef5bb9cd29b7f2f0331ea5184ea"
uuid = "f5851436-0d7a-5f13-b9de-f02708fd171a"
version = "3.3.10+0"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "3c041d2ac0a52a12a27af2782b34900d9c3ee68c"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.11.1"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "21efd19106a55620a188615da6d3d06cd7f6ee03"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.13.93+0"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "87eb71354d8ec1a96d4a7636bd57a7347dde3ef9"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.10.4+0"

[[deps.FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "aa31987c2ba8704e23c6c8ba8a4f769d5d7e4f91"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.10+0"

[[deps.GLFW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libglvnd_jll", "Pkg", "Xorg_libXcursor_jll", "Xorg_libXi_jll", "Xorg_libXinerama_jll", "Xorg_libXrandr_jll"]
git-tree-sha1 = "0c603255764a1fa0b61752d2bec14cfbd18f7fe8"
uuid = "0656b61e-2033-5cc2-a64a-77c0f6c09b89"
version = "3.3.5+1"

[[deps.GR]]
deps = ["Base64", "DelimitedFiles", "GR_jll", "HTTP", "JSON", "Libdl", "LinearAlgebra", "Pkg", "Printf", "Random", "Serialization", "Sockets", "Test", "UUIDs"]
git-tree-sha1 = "d189c6d2004f63fd3c91748c458b09f26de0efaa"
uuid = "28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"
version = "0.61.0"

[[deps.GR_jll]]
deps = ["Artifacts", "Bzip2_jll", "Cairo_jll", "FFMPEG_jll", "Fontconfig_jll", "GLFW_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pixman_jll", "Pkg", "Qt5Base_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "cafe0823979a5c9bff86224b3b8de29ea5a44b2e"
uuid = "d2c73de3-f751-5644-a686-071e5b155ba9"
version = "0.61.0+0"

[[deps.GZip]]
deps = ["Libdl"]
git-tree-sha1 = "039be665faf0b8ae36e089cd694233f5dee3f7d6"
uuid = "92fee26a-97fe-5a0c-ad85-20a5f3185b63"
version = "0.5.1"

[[deps.GeometryBasics]]
deps = ["EarCut_jll", "IterTools", "LinearAlgebra", "StaticArrays", "StructArrays", "Tables"]
git-tree-sha1 = "58bcdf5ebc057b085e58d95c138725628dd7453c"
uuid = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
version = "0.4.1"

[[deps.Gettext_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "9b02998aba7bf074d14de89f9d37ca24a1a0b046"
uuid = "78b55507-aeef-58d4-861c-77aaff3498b1"
version = "0.21.0+0"

[[deps.Glib_jll]]
deps = ["Artifacts", "Gettext_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "7bf67e9a481712b3dbe9cb3dac852dc4b1162e02"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.68.3+0"

[[deps.Graphics]]
deps = ["Colors", "LinearAlgebra", "NaNMath"]
git-tree-sha1 = "1c5a84319923bea76fa145d49e93aa4394c73fc2"
uuid = "a2bd30eb-e257-5431-a919-1863eab51364"
version = "1.1.1"

[[deps.Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "344bf40dcab1073aca04aa0df4fb092f920e4011"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.14+0"

[[deps.Grisu]]
git-tree-sha1 = "53bb909d1151e57e2484c3d1b53e19552b887fb2"
uuid = "42e2da0e-8278-4e71-bc24-59509adca0fe"
version = "1.0.2"

[[deps.HDF5]]
deps = ["Blosc", "Compat", "HDF5_jll", "Libdl", "Mmap", "Random", "Requires"]
git-tree-sha1 = "698c099c6613d7b7f151832868728f426abe698b"
uuid = "f67ccb44-e63f-5c2f-98bd-6dc0ccc4ba2f"
version = "0.15.7"

[[deps.HDF5_jll]]
deps = ["Artifacts", "JLLWrappers", "LibCURL_jll", "Libdl", "OpenSSL_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "fd83fa0bde42e01952757f01149dd968c06c4dba"
uuid = "0234f1f7-429e-5d53-9886-15a909be8d59"
version = "1.12.0+1"

[[deps.HTTP]]
deps = ["Base64", "Dates", "IniFile", "Logging", "MbedTLS", "NetworkOptions", "Sockets", "URIs"]
git-tree-sha1 = "14eece7a3308b4d8be910e265c724a6ba51a9798"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "0.9.16"

[[deps.HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg"]
git-tree-sha1 = "8a954fed8ac097d5be04921d595f741115c1b2ad"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "2.8.1+0"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[deps.HypertextLiteral]]
git-tree-sha1 = "5efcf53d798efede8fee5b2c8b09284be359bf24"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.2"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[deps.IdentityRanges]]
deps = ["OffsetArrays"]
git-tree-sha1 = "be8fcd695c4da16a1d6d0cd213cb88090a150e3b"
uuid = "bbac6d45-d8f3-5730-bfe4-7a449cd117ca"
version = "0.3.1"

[[deps.IfElse]]
git-tree-sha1 = "28e837ff3e7a6c3cdb252ce49fb412c8eb3caeef"
uuid = "615f187c-cbe4-4ef1-ba3b-2fcf58d6d173"
version = "0.1.0"

[[deps.ImageAxes]]
deps = ["AxisArrays", "ImageCore", "Reexport", "SimpleTraits"]
git-tree-sha1 = "794ad1d922c432082bc1aaa9fa8ffbd1fe74e621"
uuid = "2803e5a7-5153-5ecf-9a86-9b4c37f5f5ac"
version = "0.6.9"

[[deps.ImageContrastAdjustment]]
deps = ["ColorVectorSpace", "ImageCore", "ImageTransformations", "Parameters"]
git-tree-sha1 = "2e6084db6cccab11fe0bc3e4130bd3d117092ed9"
uuid = "f332f351-ec65-5f6a-b3d1-319c6670881a"
version = "0.3.7"

[[deps.ImageCore]]
deps = ["AbstractFFTs", "Colors", "FixedPointNumbers", "Graphics", "MappedArrays", "MosaicViews", "OffsetArrays", "PaddedViews", "Reexport"]
git-tree-sha1 = "db645f20b59f060d8cfae696bc9538d13fd86416"
uuid = "a09fc81d-aa75-5fe9-8630-4744c3626534"
version = "0.8.22"

[[deps.ImageDistances]]
deps = ["ColorVectorSpace", "Distances", "ImageCore", "ImageMorphology", "LinearAlgebra", "Statistics"]
git-tree-sha1 = "6378c34a3c3a216235210d19b9f495ecfff2f85f"
uuid = "51556ac3-7006-55f5-8cb3-34580c88182d"
version = "0.2.13"

[[deps.ImageFiltering]]
deps = ["CatIndices", "ColorVectorSpace", "ComputationalResources", "DataStructures", "FFTViews", "FFTW", "ImageCore", "LinearAlgebra", "OffsetArrays", "Requires", "SparseArrays", "StaticArrays", "Statistics", "TiledIteration"]
git-tree-sha1 = "bf96839133212d3eff4a1c3a80c57abc7cfbf0ce"
uuid = "6a3955dd-da59-5b1f-98d4-e7296123deb5"
version = "0.6.21"

[[deps.ImageIO]]
deps = ["FileIO", "Netpbm", "OpenEXR", "PNGFiles", "TiffImages", "UUIDs"]
git-tree-sha1 = "a2951c93684551467265e0e32b577914f69532be"
uuid = "82e4d734-157c-48bb-816b-45c225c6df19"
version = "0.5.9"

[[deps.ImageMagick]]
deps = ["FileIO", "ImageCore", "ImageMagick_jll", "InteractiveUtils", "Libdl", "Pkg", "Random"]
git-tree-sha1 = "5bc1cb62e0c5f1005868358db0692c994c3a13c6"
uuid = "6218d12a-5da1-5696-b52f-db25d2ecc6d1"
version = "1.2.1"

[[deps.ImageMagick_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pkg", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "ea2b6fd947cdfc43c6b8c15cff982533ec1f72cd"
uuid = "c73af94c-d91f-53ed-93a7-00f77d67a9d7"
version = "6.9.12+0"

[[deps.ImageMetadata]]
deps = ["AxisArrays", "ColorVectorSpace", "ImageAxes", "ImageCore", "IndirectArrays"]
git-tree-sha1 = "ae76038347dc4edcdb06b541595268fca65b6a42"
uuid = "bc367c6b-8a6b-528e-b4bd-a4b897500b49"
version = "0.9.5"

[[deps.ImageMorphology]]
deps = ["ColorVectorSpace", "ImageCore", "LinearAlgebra", "TiledIteration"]
git-tree-sha1 = "68e7cbcd7dfaa3c2f74b0a8ab3066f5de8f2b71d"
uuid = "787d08f9-d448-5407-9aad-5290dd7ab264"
version = "0.2.11"

[[deps.ImageQualityIndexes]]
deps = ["ColorVectorSpace", "ImageCore", "ImageDistances", "ImageFiltering", "OffsetArrays", "Statistics"]
git-tree-sha1 = "1198f85fa2481a3bb94bf937495ba1916f12b533"
uuid = "2996bd0c-7a13-11e9-2da2-2f5ce47296a9"
version = "0.2.2"

[[deps.ImageShow]]
deps = ["Base64", "FileIO", "ImageCore", "OffsetArrays", "Requires", "StackViews"]
git-tree-sha1 = "832abfd709fa436a562db47fd8e81377f72b01f9"
uuid = "4e3cecfd-b093-5904-9786-8bbb286a6a31"
version = "0.3.1"

[[deps.ImageTransformations]]
deps = ["AxisAlgorithms", "ColorVectorSpace", "CoordinateTransformations", "IdentityRanges", "ImageCore", "Interpolations", "OffsetArrays", "Rotations", "StaticArrays"]
git-tree-sha1 = "e4cc551e4295a5c96545bb3083058c24b78d4cf0"
uuid = "02fcd773-0e25-5acc-982a-7f6622650795"
version = "0.8.13"

[[deps.Images]]
deps = ["AxisArrays", "Base64", "ColorVectorSpace", "FileIO", "Graphics", "ImageAxes", "ImageContrastAdjustment", "ImageCore", "ImageDistances", "ImageFiltering", "ImageIO", "ImageMagick", "ImageMetadata", "ImageMorphology", "ImageQualityIndexes", "ImageShow", "ImageTransformations", "IndirectArrays", "OffsetArrays", "Random", "Reexport", "SparseArrays", "StaticArrays", "Statistics", "StatsBase", "TiledIteration"]
git-tree-sha1 = "8b714d5e11c91a0d945717430ec20f9251af4bd2"
uuid = "916415d5-f1e6-5110-898d-aaa5f9f070e0"
version = "0.24.1"

[[deps.Imath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "87f7662e03a649cffa2e05bf19c303e168732d3e"
uuid = "905a6f67-0a94-5f89-b386-d35d92009cd1"
version = "3.1.2+0"

[[deps.IndirectArrays]]
git-tree-sha1 = "c2a145a145dc03a7620af1444e0264ef907bd44f"
uuid = "9b13fd28-a010-5f03-acff-a1bbcff69959"
version = "0.5.1"

[[deps.Inflate]]
git-tree-sha1 = "f5fc07d4e706b84f72d54eedcc1c13d92fb0871c"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.2"

[[deps.IniFile]]
deps = ["Test"]
git-tree-sha1 = "098e4d2c533924c921f9f9847274f2ad89e018b8"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.0"

[[deps.IntelOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "d979e54b71da82f3a65b62553da4fc3d18c9004c"
uuid = "1d5cc7b8-4909-519e-a0f8-d0f5ad9712d0"
version = "2018.0.3+2"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.Interpolations]]
deps = ["AxisAlgorithms", "ChainRulesCore", "LinearAlgebra", "OffsetArrays", "Random", "Ratios", "Requires", "SharedArrays", "SparseArrays", "StaticArrays", "WoodburyMatrices"]
git-tree-sha1 = "61aa005707ea2cebf47c8d780da8dc9bc4e0c512"
uuid = "a98d9a8b-a2ab-59e6-89dd-64a1c18fca59"
version = "0.13.4"

[[deps.IntervalSets]]
deps = ["Dates", "EllipsisNotation", "Statistics"]
git-tree-sha1 = "3cc368af3f110a767ac786560045dceddfc16758"
uuid = "8197267c-284f-5f27-9208-e0e47529a953"
version = "0.5.3"

[[deps.InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "f0c6489b12d28fb4c2103073ec7452f3423bd308"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.1"

[[deps.IrrationalConstants]]
git-tree-sha1 = "7fd44fd4ff43fc60815f8e764c0f352b83c49151"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.1"

[[deps.IterTools]]
git-tree-sha1 = "05110a2ab1fc5f932622ffea2a003221f4782c18"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.3.0"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "642a199af8b68253517b80bd3bfd17eb4e84df6e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.3.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "8076680b162ada2a031f707ac7b4953e30667a37"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.2"

[[deps.JSON3]]
deps = ["Dates", "Mmap", "Parsers", "StructTypes", "UUIDs"]
git-tree-sha1 = "7d58534ffb62cd947950b3aa9b993e63307a6125"
uuid = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
version = "1.9.2"

[[deps.JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "d735490ac75c5cb9f1b00d8b5509c11984dc6943"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "2.1.0+0"

[[deps.LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6250b16881adf048549549fba48b1161acdac8c"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.1+0"

[[deps.LZO_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e5b909bcf985c5e2605737d2ce278ed791b89be6"
uuid = "dd4b983a-f0e5-5f8d-a1b7-129d4a5fb1ac"
version = "2.10.1+0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "c7f1c695e06c01b95a67f0cd1d34994f3e7db104"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.2.1"

[[deps.Latexify]]
deps = ["Formatting", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "Printf", "Requires"]
git-tree-sha1 = "a8f4f279b6fa3c3c4f1adadd78a621b13a506bce"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.15.9"

[[deps.LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "761a393aeccd6aa92ec3515e428c26bf99575b3b"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.2.2+0"

[[deps.Libgcrypt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgpg_error_jll", "Pkg"]
git-tree-sha1 = "64613c82a59c120435c067c2b809fc61cf5166ae"
uuid = "d4300ac3-e22c-5743-9152-c294e39db1e4"
version = "1.8.7+0"

[[deps.Libglvnd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll", "Xorg_libXext_jll"]
git-tree-sha1 = "7739f837d6447403596a75d19ed01fd08d6f56bf"
uuid = "7e76a0d4-f3c7-5321-8279-8d96eeed0f29"
version = "1.3.0+3"

[[deps.Libgpg_error_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c333716e46366857753e273ce6a69ee0945a6db9"
uuid = "7add5ba3-2f88-524e-9cd5-f83b8a55f7b8"
version = "1.42.0+0"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "42b62845d70a619f063a7da093d995ec8e15e778"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.16.1+1"

[[deps.Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c30530bf0effd46e15e0fdcf2b8636e78cbbd73"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.35.0+0"

[[deps.Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Pkg", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "340e257aada13f95f98ee352d316c3bed37c8ab9"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.3.0+0"

[[deps.Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "7f3efec06033682db852f8b3bc3c1d2b0a0ab066"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.36.0+0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["ChainRulesCore", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "6193c3815f13ba1b78a51ce391db8be016ae9214"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.4"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.Lz4_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "5d494bc6e85c4c9b626ee0cab05daa4085486ab1"
uuid = "5ced341a-0733-55b8-9ab6-a4889d929147"
version = "1.9.3+0"

[[deps.MAT]]
deps = ["BufferedStreams", "CodecZlib", "HDF5", "SparseArrays"]
git-tree-sha1 = "5c62992f3d46b8dce69bdd234279bb5a369db7d5"
uuid = "23992714-dd62-5051-b70f-ba57cb901cac"
version = "0.10.1"

[[deps.MKL_jll]]
deps = ["Artifacts", "IntelOpenMP_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "Pkg"]
git-tree-sha1 = "5455aef09b40e5020e1520f551fa3135040d4ed0"
uuid = "856f044c-d86e-5d09-b602-aeab76dc8ba7"
version = "2021.1.1+2"

[[deps.MLDatasets]]
deps = ["BinDeps", "ColorTypes", "DataDeps", "DelimitedFiles", "FixedPointNumbers", "GZip", "JSON3", "MAT", "PyCall", "Requires"]
git-tree-sha1 = "3ad568c323866280500096860a5e2a76b2e7e12d"
uuid = "eb30cadb-4394-5ae3-aed4-317e484a6458"
version = "0.5.12"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "5a5bc6bf062f0f95e62d0fe0a2d99699fed82dd9"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.8"

[[deps.MappedArrays]]
git-tree-sha1 = "e8b359ef06ec72e8c030463fe02efe5527ee5142"
uuid = "dbb5928d-eab1-5f90-85c2-b9b0edb7c900"
version = "0.4.1"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "Random", "Sockets"]
git-tree-sha1 = "1c38e51c3d08ef2278062ebceade0e46cefc96fe"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.0.3"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[deps.Measures]]
git-tree-sha1 = "e498ddeee6f9fdb4551ce855a46f54dbd900245f"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.1"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "bf210ce90b6c9eed32d25dbcae1ebc565df2687f"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.2"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MosaicViews]]
deps = ["MappedArrays", "OffsetArrays", "PaddedViews", "StackViews"]
git-tree-sha1 = "b34e3bc3ca7c94914418637cb10cc4d1d80d877d"
uuid = "e94cdb99-869f-56ef-bcf0-1ae2bcbe0389"
version = "0.3.3"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[deps.NaNMath]]
git-tree-sha1 = "bfe47e760d60b82b66b61d2d44128b62e3a369fb"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "0.3.5"

[[deps.Netpbm]]
deps = ["ColorVectorSpace", "FileIO", "ImageCore"]
git-tree-sha1 = "09589171688f0039f13ebe0fdcc7288f50228b52"
uuid = "f09324ee-3d7c-5217-9330-fc30815ba969"
version = "1.0.1"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[deps.OffsetArrays]]
deps = ["Adapt"]
git-tree-sha1 = "c0e9e582987d36d5a61e650e6e543b9e44d9914b"
uuid = "6fe1bfb0-de20-5000-8ca7-80f57d26f881"
version = "1.10.7"

[[deps.Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "7937eda4681660b4d6aeeecc2f7e1c81c8ee4e2f"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.5+0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"

[[deps.OpenEXR]]
deps = ["Colors", "FileIO", "OpenEXR_jll"]
git-tree-sha1 = "327f53360fdb54df7ecd01e96ef1983536d1e633"
uuid = "52e1d378-f018-4a11-a4be-720524705ac7"
version = "0.3.2"

[[deps.OpenEXR_jll]]
deps = ["Artifacts", "Imath_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "923319661e9a22712f24596ce81c54fc0366f304"
uuid = "18a262bb-aa17-5467-a713-aee519bc75cb"
version = "3.1.1+0"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "15003dcb7d8db3c6c857fda14891a539a8f2705a"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.10+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51a08fb14ec28da2ec7a927c4337e4332c2a4720"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.3.2+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.PCRE_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b2a7af664e098055a7529ad1a900ded962bca488"
uuid = "2f80f16e-611a-54ab-bc61-aa92de5b98fc"
version = "8.44.0+0"

[[deps.PNGFiles]]
deps = ["Base64", "CEnum", "ImageCore", "IndirectArrays", "OffsetArrays", "libpng_jll"]
git-tree-sha1 = "33ae7d19c6ba748d30c0c08a82378aae7b64b5e9"
uuid = "f57f5aa1-a3ce-4bc8-8ab9-96f992907883"
version = "0.3.11"

[[deps.PaddedViews]]
deps = ["OffsetArrays"]
git-tree-sha1 = "646eed6f6a5d8df6708f15ea7e02a7a2c4fe4800"
uuid = "5432bcbf-9aad-5242-b902-cca2824c8663"
version = "0.5.10"

[[deps.Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[deps.Parsers]]
deps = ["Dates"]
git-tree-sha1 = "d911b6a12ba974dabe2291c6d450094a7226b372"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.1.1"

[[deps.Pixman_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b4f5d02549a10e20780a24fce72bea96b6329e29"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.40.1+0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[deps.PkgVersion]]
deps = ["Pkg"]
git-tree-sha1 = "a7a7e1a88853564e551e4eba8650f8c38df79b37"
uuid = "eebad327-c553-4316-9ea0-9fa01ccd7688"
version = "0.1.1"

[[deps.PlotThemes]]
deps = ["PlotUtils", "Requires", "Statistics"]
git-tree-sha1 = "a3a964ce9dc7898193536002a6dd892b1b5a6f1d"
uuid = "ccf2f8ad-2431-5c83-bf29-c5338b663b6a"
version = "2.0.1"

[[deps.PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "Printf", "Random", "Reexport", "Statistics"]
git-tree-sha1 = "b084324b4af5a438cd63619fd006614b3b20b87b"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.0.15"

[[deps.Plots]]
deps = ["Base64", "Contour", "Dates", "Downloads", "FFMPEG", "FixedPointNumbers", "GR", "GeometryBasics", "JSON", "Latexify", "LinearAlgebra", "Measures", "NaNMath", "PlotThemes", "PlotUtils", "Printf", "REPL", "Random", "RecipesBase", "RecipesPipeline", "Reexport", "Requires", "Scratch", "Showoff", "SparseArrays", "Statistics", "StatsBase", "UUIDs"]
git-tree-sha1 = "25007065fa36f272661a0e1968761858cc880755"
uuid = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
version = "1.23.1"

[[deps.PlutoUI]]
deps = ["Base64", "Dates", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "UUIDs"]
git-tree-sha1 = "4c8a7d080daca18545c56f1cac28710c362478f3"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.16"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "00cfd92944ca9c760982747e9a1d0d5d86ab1e5a"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.2.2"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[deps.ProgressMeter]]
deps = ["Distributed", "Printf"]
git-tree-sha1 = "afadeba63d90ff223a6a48d2009434ecee2ec9e8"
uuid = "92933f4c-e287-5a05-a399-4b506db050ca"
version = "1.7.1"

[[deps.PyCall]]
deps = ["Conda", "Dates", "Libdl", "LinearAlgebra", "MacroTools", "Serialization", "VersionParsing"]
git-tree-sha1 = "4ba3651d33ef76e24fef6a598b63ffd1c5e1cd17"
uuid = "438e738f-606a-5dbb-bf0a-cddfbfd45ab0"
version = "1.92.5"

[[deps.Qt5Base_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Fontconfig_jll", "Glib_jll", "JLLWrappers", "Libdl", "Libglvnd_jll", "OpenSSL_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libxcb_jll", "Xorg_xcb_util_image_jll", "Xorg_xcb_util_keysyms_jll", "Xorg_xcb_util_renderutil_jll", "Xorg_xcb_util_wm_jll", "Zlib_jll", "xkbcommon_jll"]
git-tree-sha1 = "ad368663a5e20dbb8d6dc2fddeefe4dae0781ae8"
uuid = "ea2cea3b-5b76-57ae-a6ef-0a8af62496e1"
version = "5.15.3+0"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.RangeArrays]]
git-tree-sha1 = "b9039e93773ddcfc828f12aadf7115b4b4d225f5"
uuid = "b3c3ace0-ae52-54e7-9d0b-2c1406fd6b9d"
version = "0.3.2"

[[deps.Ratios]]
deps = ["Requires"]
git-tree-sha1 = "01d341f502250e81f6fec0afe662aa861392a3aa"
uuid = "c84ed2f1-dad5-54f0-aa8e-dbefe2724439"
version = "0.4.2"

[[deps.RecipesBase]]
git-tree-sha1 = "44a75aa7a527910ee3d1751d1f0e4148698add9e"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.1.2"

[[deps.RecipesPipeline]]
deps = ["Dates", "NaNMath", "PlotUtils", "RecipesBase"]
git-tree-sha1 = "7ad0dfa8d03b7bcf8c597f59f5292801730c55b8"
uuid = "01d81517-befc-4cb6-b9ec-a95719d0359c"
version = "0.4.1"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "4036a3bd08ac7e968e27c203d45f5fff15020621"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.1.3"

[[deps.Rotations]]
deps = ["LinearAlgebra", "Random", "StaticArrays", "Statistics"]
git-tree-sha1 = "3313a251b7af2c616534e6f3764d444782cb84d7"
uuid = "6038ab10-8711-5258-84ad-4b1120ba62dc"
version = "1.0.3"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "0b4b7f1393cff97c33891da2a0bf69c6ed241fda"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.1.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.Showoff]]
deps = ["Dates", "Grisu"]
git-tree-sha1 = "91eddf657aca81df9ae6ceb20b959ae5653ad1de"
uuid = "992d4aef-0814-514b-bc4d-f2e9a6c4116f"
version = "1.0.3"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "f0bccf98e16759818ffc5d97ac3ebf87eb950150"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "1.8.1"

[[deps.StackViews]]
deps = ["OffsetArrays"]
git-tree-sha1 = "46e589465204cd0c08b4bd97385e4fa79a0c770c"
uuid = "cae243ae-269e-4f55-b966-ac2d0dc13c15"
version = "0.1.1"

[[deps.Static]]
deps = ["IfElse"]
git-tree-sha1 = "e7bc80dc93f50857a5d1e3c8121495852f407e6a"
uuid = "aedffcd0-7271-4cad-89d0-dc628f76c6d3"
version = "0.4.0"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "Random", "Statistics"]
git-tree-sha1 = "3c76dde64d03699e074ac02eb2e8ba8254d428da"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.2.13"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StatsAPI]]
git-tree-sha1 = "1958272568dc176a1d881acb797beb909c785510"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.0.0"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "eb35dcc66558b2dda84079b9a1be17557d32091a"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.12"

[[deps.StringDistances]]
deps = ["Distances", "StatsAPI"]
git-tree-sha1 = "00e86048552d34bb486cad935754dd9516bdb46e"
uuid = "88034a9c-02f8-509d-84a9-84ec65e18404"
version = "0.11.1"

[[deps.StructArrays]]
deps = ["Adapt", "DataAPI", "StaticArrays", "Tables"]
git-tree-sha1 = "2ce41e0d042c60ecd131e9fb7154a3bfadbf50d3"
uuid = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
version = "0.6.3"

[[deps.StructTypes]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "d24a825a95a6d98c385001212dc9020d609f2d4f"
uuid = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
version = "1.8.1"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "TableTraits", "Test"]
git-tree-sha1 = "fed34d0e71b91734bf0a7e10eb1bb05296ddbcd0"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.6.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[deps.TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TestImages]]
deps = ["AxisArrays", "ColorTypes", "FileIO", "OffsetArrays", "Pkg", "StringDistances"]
git-tree-sha1 = "f91d170645a8ba6fbaa3ac2879eca5da3d92a31a"
uuid = "5e47fb64-e119-507b-a336-dd2b206d9990"
version = "1.6.2"

[[deps.TiffImages]]
deps = ["ColorTypes", "DataStructures", "DocStringExtensions", "FileIO", "FixedPointNumbers", "IndirectArrays", "Inflate", "OffsetArrays", "PkgVersion", "ProgressMeter", "UUIDs"]
git-tree-sha1 = "016185e1a16c1bd83a4352b19a3b136224f22e38"
uuid = "731e570b-9d59-4bfa-96dc-6df516fadf69"
version = "0.5.1"

[[deps.TiledIteration]]
deps = ["OffsetArrays"]
git-tree-sha1 = "5683455224ba92ef59db72d10690690f4a8dc297"
uuid = "06e1c1a7-607b-532d-9fad-de7d9aa2abac"
version = "0.3.1"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "216b95ea110b5972db65aa90f88d8d89dcb8851c"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.6"

[[deps.URIParser]]
deps = ["Unicode"]
git-tree-sha1 = "53a9f49546b8d2dd2e688d216421d050c9a31d0d"
uuid = "30578b45-9adc-5946-b283-645ec420af67"
version = "0.4.1"

[[deps.URIs]]
git-tree-sha1 = "97bbe755a53fe859669cd907f2d96aee8d2c1355"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.3.0"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.VersionParsing]]
git-tree-sha1 = "e575cf85535c7c3292b4d89d89cc29e8c3098e47"
uuid = "81def892-9a0e-5fdd-b105-ffc91e053289"
version = "1.2.1"

[[deps.Wayland_jll]]
deps = ["Artifacts", "Expat_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "3e61f0b86f90dacb0bc0e73a0c5a83f6a8636e23"
uuid = "a2964d1f-97da-50d4-b82a-358c7fce9d89"
version = "1.19.0+0"

[[deps.Wayland_protocols_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Wayland_jll"]
git-tree-sha1 = "2839f1c1296940218e35df0bbb220f2a79686670"
uuid = "2381bf8a-dfd0-557d-9999-79630e7b1b91"
version = "1.18.0+4"

[[deps.WoodburyMatrices]]
deps = ["LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "de67fa59e33ad156a590055375a30b23c40299d3"
uuid = "efce3f68-66dc-5838-9240-27a6d6f5f9b6"
version = "0.5.5"

[[deps.XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "1acf5bdf07aa0907e0a37d3718bb88d4b687b74a"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.9.12+0"

[[deps.XSLT_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgcrypt_jll", "Libgpg_error_jll", "Libiconv_jll", "Pkg", "XML2_jll", "Zlib_jll"]
git-tree-sha1 = "91844873c4085240b95e795f692c4cec4d805f8a"
uuid = "aed1982a-8fda-507f-9586-7b0439959a61"
version = "1.1.34+0"

[[deps.Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "5be649d550f3f4b95308bf0183b82e2582876527"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.6.9+4"

[[deps.Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4e490d5c960c314f33885790ed410ff3a94ce67e"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.9+4"

[[deps.Xorg_libXcursor_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXfixes_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "12e0eb3bc634fa2080c1c37fccf56f7c22989afd"
uuid = "935fb764-8cf2-53bf-bb30-45bb1f8bf724"
version = "1.2.0+4"

[[deps.Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fe47bd2247248125c428978740e18a681372dd4"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.3+4"

[[deps.Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "b7c0aa8c376b31e4852b360222848637f481f8c3"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.4+4"

[[deps.Xorg_libXfixes_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "0e0dc7431e7a0587559f9294aeec269471c991a4"
uuid = "d091e8ba-531a-589c-9de9-94069b037ed8"
version = "5.0.3+4"

[[deps.Xorg_libXi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXfixes_jll"]
git-tree-sha1 = "89b52bc2160aadc84d707093930ef0bffa641246"
uuid = "a51aa0fd-4e3c-5386-b890-e753decda492"
version = "1.7.10+4"

[[deps.Xorg_libXinerama_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll"]
git-tree-sha1 = "26be8b1c342929259317d8b9f7b53bf2bb73b123"
uuid = "d1454406-59df-5ea1-beac-c340f2130bc3"
version = "1.1.4+4"

[[deps.Xorg_libXrandr_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "34cea83cb726fb58f325887bf0612c6b3fb17631"
uuid = "ec84b674-ba8e-5d96-8ba1-2a689ba10484"
version = "1.5.2+4"

[[deps.Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "19560f30fd49f4d4efbe7002a1037f8c43d43b96"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.10+4"

[[deps.Xorg_libpthread_stubs_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6783737e45d3c59a4a4c4091f5f88cdcf0908cbb"
uuid = "14d82f49-176c-5ed1-bb49-ad3f5cbd8c74"
version = "0.1.0+3"

[[deps.Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "XSLT_jll", "Xorg_libXau_jll", "Xorg_libXdmcp_jll", "Xorg_libpthread_stubs_jll"]
git-tree-sha1 = "daf17f441228e7a3833846cd048892861cff16d6"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.13.0+3"

[[deps.Xorg_libxkbfile_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "926af861744212db0eb001d9e40b5d16292080b2"
uuid = "cc61e674-0454-545c-8b26-ed2c68acab7a"
version = "1.1.0+4"

[[deps.Xorg_xcb_util_image_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "0fab0a40349ba1cba2c1da699243396ff8e94b97"
uuid = "12413925-8142-5f55-bb0e-6d7ca50bb09b"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll"]
git-tree-sha1 = "e7fd7b2881fa2eaa72717420894d3938177862d1"
uuid = "2def613f-5ad1-5310-b15b-b15d46f528f5"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_keysyms_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "d1151e2c45a544f32441a567d1690e701ec89b00"
uuid = "975044d2-76e6-5fbe-bf08-97ce7c6574c7"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_renderutil_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "dfd7a8f38d4613b6a575253b3174dd991ca6183e"
uuid = "0d47668e-0667-5a69-a72c-f761630bfb7e"
version = "0.3.9+1"

[[deps.Xorg_xcb_util_wm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "e78d10aab01a4a154142c5006ed44fd9e8e31b67"
uuid = "c22f9ab0-d5fe-5066-847c-f4bb1cd4e361"
version = "0.4.1+1"

[[deps.Xorg_xkbcomp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxkbfile_jll"]
git-tree-sha1 = "4bcbf660f6c2e714f87e960a171b119d06ee163b"
uuid = "35661453-b289-5fab-8a00-3d9160c6a3a4"
version = "1.4.2+4"

[[deps.Xorg_xkeyboard_config_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xkbcomp_jll"]
git-tree-sha1 = "5c8424f8a67c3f2209646d4425f3d415fee5931d"
uuid = "33bec58e-1273-512f-9401-5d533626f822"
version = "2.27.0+4"

[[deps.Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "79c31e7844f6ecf779705fbc12146eb190b7d845"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.4.0+3"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[deps.Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "cc4bf3fdde8b7e3e9fa0351bdeedba1cf3b7f6e6"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.0+0"

[[deps.libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "5982a94fcba20f02f42ace44b9894ee2b140fe47"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.15.1+0"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"

[[deps.libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "daacc84a041563f965be61859a36e17c4e4fcd55"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.2+0"

[[deps.libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "94d180a6d2b5e55e447e2d27a29ed04fe79eb30c"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.38+0"

[[deps.libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll", "Pkg"]
git-tree-sha1 = "c45f4e40e7aafe9d086379e5578947ec8b95a8fb"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.7+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"

[[deps.x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fea590b89e6ec504593146bf8b988b2c00922b2"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "2021.5.5+0"

[[deps.x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ee567a171cce03570d77ad3a43e90218e38937a9"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "3.5.0+0"

[[deps.xkbcommon_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Wayland_jll", "Wayland_protocols_jll", "Xorg_libxcb_jll", "Xorg_xkeyboard_config_jll"]
git-tree-sha1 = "ece2350174195bb31de1a63bea3a41ae1aa593b6"
uuid = "d8fb68d0-12a3-5cfd-a85a-d49703b185fd"
version = "0.9.1+5"
"""

# ╔═╡ Cell order:
# ╟─3c18930f-0d57-4f8e-ac75-7472ae3aa9d7
# ╠═8953d58d-d374-490e-a8f3-45c02c7c402b
# ╟─5b9352f6-79cd-447d-b838-435caad1fe61
# ╟─1ed1f1cc-7fa8-4106-8e8b-42c796f69d26
# ╠═46fb0d31-0ed7-4843-8d87-0e514a9a816f
# ╟─e50fe94b-1290-4915-ab12-21bb72cd1f80
# ╠═5beb84ea-7c2e-425d-ae5e-f094a69a2236
# ╟─9bfb324d-d2d9-444b-87c3-d8bd3f720bf3
# ╠═600106f0-9f85-443a-b118-958ba9114f36
# ╠═17979516-8b02-47a0-918e-f971745bd745
# ╟─b693b8b5-3672-47b1-ace9-86e67ade269d
# ╠═309034d6-9c1c-4e15-af99-c976481af9ec
# ╟─af11fa72-782e-4480-a13b-24583749b81b
# ╠═04436d60-fd1f-42ff-8921-19f066f36ef9
# ╟─b795d6e3-64bc-4edc-a65e-aa76e8d79938
# ╠═a5d52ac9-3afd-432b-ba18-ad40a43bd8f2
# ╠═b799a4de-5cca-46db-8654-7423d24d453f
# ╟─9c4dd774-13cf-4dad-a2ce-b890e6cae4ee
# ╟─14a173eb-fd20-4e98-a32a-263f70fb6f14
# ╠═6fc60f63-e6cc-4596-b924-fee0ae733fda
# ╟─86084173-0b89-433e-97a3-ee70706233e7
# ╟─9c7eaa4d-da57-4110-89b8-270aa74e1605
# ╠═57f5be0e-381a-4323-8322-1b9d5b1005de
# ╠═903fd282-8621-48a7-bfed-0c8bcdc70f41
# ╟─f5cdb1b0-8a0b-42ec-aaa2-89948d027ff5
# ╠═37913c90-1066-44e8-91ce-d7f5abdd4dc1
# ╠═424e1143-aebc-4d5b-ba92-569258c61757
# ╟─21ad8c6e-d500-4b55-b21a-02395552a8b0
# ╠═a38ef901-bcca-4b07-9be5-09dfb03ea976
# ╠═db59f087-3ddd-46a4-8c17-3acb6219c60b
# ╠═e24b29d3-5fd8-4242-81ac-174c62509f6a
# ╟─d1eb882b-8460-4f58-9ffa-23b224ae9cd3
# ╠═8dec6c6d-209c-4a9e-ab97-9f7283417aa4
# ╟─e628d4dc-8f15-4909-a434-60b596585dd2
# ╟─8f199bf9-c27d-4d5e-ae50-bfee13b01587
# ╟─30034666-8f93-41b8-9c08-a9f8ed9d70bf
# ╠═cc3447af-ed5b-426e-98d4-5213ac564390
# ╠═ade6d569-36bf-4b67-9671-7426cd079119
# ╟─3d7b8ed3-b3f2-4e1e-8075-c10e74807e58
# ╠═7f4142b8-6c19-4c03-b7bc-ab1639d1991a
# ╟─9b4389ac-e5b3-4634-aa12-860f6b581114
# ╠═e7417c94-5688-4c43-8078-5d0641cf7881
# ╟─dfc822fd-1b38-495e-b9b1-6938064b46ca
# ╟─a9ae6884-4af4-43de-8b4f-421f8ba932ef
# ╠═6e84af17-3154-49e1-8fe2-03f5301ebe63
# ╠═7488e45e-e35b-43e6-be74-d86e958ac265
# ╟─01ef7470-e3a9-4007-931f-63ffc59eec9b
# ╟─0ba41c20-42fb-40d5-a57a-e065bc6b511d
# ╠═05935ff1-f5c3-4735-93d4-9a382b921047
# ╠═f185f8bf-6cc7-4802-af85-4262315115e9
# ╠═3374b574-13c3-4249-bc22-4ccd1666330c
# ╟─de3f02d7-7718-4c23-aa1f-a1d7d34d8561
# ╟─d13dd463-2b26-4b6c-bd0f-8300db6bef2b
# ╠═54d95539-6756-46a7-9677-04d97f1d7e43
# ╟─21548a8d-eda7-4701-95c6-93c983578889
# ╟─f97da5d3-dcec-454c-b1ed-0522972e140c
# ╠═7bb39eb0-47ac-4b44-b235-ef5b6afff9f1
# ╟─7887a628-e05f-48f1-8f9d-9ea58264f65e
# ╟─1bc0bb7a-1dd2-4ed9-a2e0-9791c8d43f3e
# ╟─37cb53d6-85b9-4782-8c2d-bffda2687338
# ╠═15a050bd-4190-4bd2-b976-88fc1b48ce2a
# ╟─197cc773-8b68-458b-a32b-7b506eabca38
# ╠═35c0ad63-c3fc-4f1b-b852-b0d2db49e953
# ╟─35e7502b-f3e0-4377-9ed7-a04bb7c1d423
# ╠═db592332-5bde-47af-9609-ab41b3b47027
# ╠═f108fbfa-a3c0-4e3a-8a5a-c03b43ba9805
# ╟─f50d4326-55e4-47cb-88b8-32ba882965cf
# ╟─c02e901e-e52f-4d41-a9d1-6e7041b3fe3e
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
