### A Pluto.jl notebook ###
# v0.17.1

using Markdown
using InteractiveUtils

# ╔═╡ 5a829caf-fba9-483f-98a9-c30278f266c0
using PlutoUI, BenchmarkTools, MappedArrays, LinearAlgebra

# ╔═╡ 690c08fd-7315-4021-b060-daba5bf7ef01
function fclamp(f, X; lo=0.0, hi=1.0)
	tmp = @. clamp(X, lo, hi)
	return f(tmp)
end

# ╔═╡ f6720a0b-8dd9-47ce-91c3-410a67c2c93f
function fclamp(f::typeof(sum), X; lo=0.0, hi=1.0)
	rst = 0.0
	@inbounds @simd for x in X
		rst += clamp(x, lo, hi)
	end
	return rst
end

# ╔═╡ 3a6dc9ef-f91f-4201-b634-5d7508a03909
with_terminal() do
	X = rand(61, 61) .- 0.5
	out = @btime fclamp(sum, $X)
	nothing
end

# ╔═╡ 1a4786be-f1ab-44e3-a783-b7f0407305dd
function fclamp_lazy(f, X; lo=0.0, hi=1.0)
	# tmp = map(X) do x
	# 	clamp(x, lo, hi)
	# end
	tmp = mappedarray(X) do x
		clamp(x, lo, hi)
	end
	return f(tmp)
end

# ╔═╡ 9c1457fe-a643-4f93-9dcc-fda60b753a8d
with_terminal() do
	X = rand(61, 61) .- 0.5
	out = @btime fclamp_lazy(sum, $X)
	nothing
end

# ╔═╡ 492a4fc3-7ff3-48db-939e-059157d58cf9
with_terminal() do
	X = rand(61, 61) .- 0.5
	out = @btime mapreduce(+, $X) do x
		clamp(x, 0.0, 1.0)
	end
	nothing
end

# ╔═╡ d30fb3fb-7145-4117-9d3a-3e8b0a32031f
begin
	struct LazyArray{T, N, F, AT<:AbstractArray} <: AbstractArray{T, N}
		f::F
		data::AT
	end
	function LazyArray(f, data::AbstractArray{T,N}) where {T,N}
		LazyArray{T, N, typeof(f), typeof(data)}(f, data)
	end

	Base.size(A::LazyArray) = size(A.data)
	function Base.getindex(A::LazyArray, inds::Int...)
		# @show inds
		A.f(A.data[inds...])
	end
end

# ╔═╡ 5cc795d9-d6e4-465e-a816-8972351f2ac8
function fclamp_lazy_old(f, X; lo=0.0, hi=1.0)
	tmp = LazyArray(X) do x
		clamp(x, lo, hi)
	end
	return f(tmp)
end

# ╔═╡ 66b2df42-c98d-471b-b5d4-4e1ea7c3b866
begin
	struct LazyArrayNew{T,N} <: AbstractArray{T,N}
		f
		data::AbstractArray{T,N}
	end

	Base.size(A::LazyArrayNew) = size(A.data)
	function Base.getindex(A::LazyArrayNew, inds::Int...)
		A.f(A.data[inds...])
	end
end

# ╔═╡ c4d8eaba-44ee-11ec-21d0-0b9931dc5487
md"""
# 矩阵与迭代器协议

日期: 10月14日

作者： 陈久宁

大纲：

- 矩阵协议
- 迭代器协议

参考：

- [接口协议](https://docs.julialang.org/en/v1/manual/interfaces/)
"""

# ╔═╡ 9e816bda-81e7-4981-837d-ffa8870b8eb3
md"""
对一个容器 `X` 使用 for 循环的方式有两种：

```julia
for i in 1:length(X) # iterate -- iterator interface
    # getindex -- indexing interface
	do_something(X[i])
end
```

以及

```julia
for x in X # iterate -- iterator interface
	do_something(x)
end
```

这背后分别对应于 `X` 类型的两种协议： 矩阵（列表）协议与迭代器协议。 虽然实际情况下这两种协议经常共同存在， 但在理想情况下， 列表协议与迭代器协议大概可以如下区分：


| 类型 | 读写特征 | 是否有状态 | 接口函数 |
| --- | --- | --- | --- |
| 矩阵协议 | 随机读写 | 无状态 | `getindex` |
| 迭代器协议 | 顺序读写 | 有状态 | `iterate` |
"""

# ╔═╡ 0662c5e4-dd43-4396-bc58-9e30b9f5d85d
md"""
## 例： lazy array

由于内存分配经常会成为性能瓶颈， 因此存在很多手段来避免不必要的内存分配。 例如下面的 `fclamp` 函数使用了一个中间矩阵来存储 `clamp` 的结果， 并将结果传递给下一个函数 `f`。
"""

# ╔═╡ 00fe3392-e5ef-4dca-b7f2-41c245edbe7c
md"""
上面的内存分配是为了中间变量 `tmp` 创建的。 我们可以利用 [`MappedArray`](https://github.com/JuliaArrays/MappedArrays.jl) 或者 [`LazyArray`](https://github.com/JuliaArrays/LazyArrays.jl) 来避免它：
"""

# ╔═╡ 94e2bfab-2a42-4467-abe3-e563249bf411
md"""
注： 对于 `fclamp_lazy(sum, X)` 来说， 还可以通过 `mapreduce` 来实现：
"""

# ╔═╡ bc7b8b75-0f03-4785-8842-60fc2e64c10c
md"""
`mappedarray(f, X)` 构造了一个无内存占用的虚拟矩阵 `Y`， 其中每个元素 `Y[i] = f(X[i])`， 这背后使用的即为矩阵接口。 根据[矩阵协议](https://docs.julialang.org/en/v1/manual/interfaces/#man-interface-array)的描述， 实现一个自定义矩阵需要至少实现以下三个方法：

- `size(A)`： 定义矩阵的尺寸
- `getindex(A, inds...)`: 定义取下标的方式 `A[i]`
- `setindex!(A, v, inds...)`： 定义下标赋值 `A[i] = v`

实际上， 如果矩阵设计成只读的模式的话， 那么也可以不实现 `setindex!` 方法
"""

# ╔═╡ a6eb6c57-d6e1-4fd6-b0d0-988a9576ca50
md"""
问： 为什么不写成下面这种？

```julia
struct LazyArray <: AbstractArray
    f
    data
end
```
"""

# ╔═╡ 2c556187-0243-432c-924e-47289b7f0143
function fclamp_lazy_new(f, X; lo=0.0, hi=1.0)
	# tmp = map(X) do x
	# 	clamp(x, lo, hi)
	# end
	tmp = LazyArrayNew(X) do x
		clamp(x, lo, hi)
	end
	return f(tmp)
end

# ╔═╡ 94fcaf12-09ca-44c0-b1d4-5ad7198c2380
with_terminal() do
	X = rand(4, 4)
	@btime fclamp_lazy_old(sum, $X)
	@btime fclamp_lazy_new(sum, $X)
end

# ╔═╡ 3c4f5938-21dd-464e-9037-2203e3f75eae
LazyArray(rand(4, 4)) do x
	clamp(x, 0.2, 0.5)
end

# ╔═╡ f00e6fe3-a790-4057-8032-877798d2d441
md"""

区别于正常的矩阵， `LazyArray` 中并没有存储实际值， 而是在需要的时候 (即调用 `X[i]`) 的时候进行一次现场的运算。 这种计算模式称为 lazy evaluation， 区别于普通矩阵的 eager evaluation.

| 模式 | 使用方式 | 内存 | 计算 |
| --- | --- | --- | --- |
| lazy mode | `mappedarray(f, X)` | 无内存开销 | 有重复计算 |
| eager mode | `map(f, X)` | 有内存开销 | 无重复计算 |

这里的重复计算体现在多次对同一下标进行取值的过程中。 换句话说， Lazy array 是一种典型的[时间换空间](https://en.wikipedia.org/wiki/Space%E2%80%93time_tradeoff)的策略.

这种 lazy evaluation 技术存在一些典型的应用场景：

- 当底层计算中内存分配的开销大于实际计算的开销时， 可以使用 Lazy array 来避免不必要的内存创建
- 当 `X` 的数据量足够大以至于计算机硬件没有办法分配足够的空间给 `map(f, X)` 时， 使用 Lazy array 可以让由于内存限制导致不可计算的任务变得可以计算。 这在大数据和深度学习领域非常常见。
"""

# ╔═╡ 55d4d2e9-e6cc-4f7e-8701-173c19167fd4
md"""
!!! note "小练习"
	利用矩阵接口实现一个简单的对角线矩阵 `MyDiagonal`， 并与 `LinearAlgebra` 里的 `Diagonal` 进行结果和性能的对比。
    提示： 利用 `@inbounds` 或 `Base.@propagate_inbounds` 标记来避免不必要的边界检查来得到一定的性能加速。
"""

# ╔═╡ b4b49b06-ea1a-422f-b430-81a5714b4993
with_terminal() do
	# Diagonal
	X = Diagonal(rand(101))
	@btime sum($X)
	@btime ($X * $X)
	# Array
	X = collect(X)
	@btime sum($X)
	@btime ($X * $X)
	nothing
end

# ╔═╡ fad0be89-5709-41d0-b6fd-26e12f33be26
md"""
## 例： Repeat Iterator

在不创建内存的情况下， 如何将同一个 `X` 循环多次？

很自然的一个想法是再套一层循环：
"""

# ╔═╡ ac26d319-e7d8-4c3a-b108-6f7648cea145
with_terminal() do
	X = [1, 2, 3]
	n = 2
	for i in 1:n
		for x in X
			println("epoch $i: $x")
		end
	end
end

# ╔═╡ 3de702a4-93bc-41ad-a4d4-f5605d791894
md"""
这件事情实际上也可以使用 Repeated 迭代器来实现
"""

# ╔═╡ a26b7615-ee4d-44ce-8b12-346b6e438ee4
with_terminal() do
	@btime Iterators.repeated($(rand(4, 4)), 10)
end

# ╔═╡ abb1703c-221e-40f7-a1f7-2a5f4492de41
with_terminal() do
	X = [1, 2, 3]
	for X_i in Iterators.repeated(X, 2)
		for x in X_i
			println(x)
		end
	end
end

# ╔═╡ 4efbc992-9102-4a94-bb8a-29e75ac09389
md"""
根据[迭代器协议](https://docs.julialang.org/en/v1/manual/interfaces/#man-interface-iteration)的说明， 实现一个迭代器需要定义至少以下两个方法：

- `iterate(iter) -> (xᵢ, stateᵢ)`： 返回迭代器的第一个值与初始状态
- `iterate(iter, stateᵢ) -> (xᵢ₊₁, stateᵢ₊₁)`： 根据迭代器的第i个状态输入， 返回第 i+1 个值与下一个状态

当迭代器需要结束的时候， 返回 `nothing`
"""

# ╔═╡ eee131cc-ed80-4b86-bcc9-5a090296a16a
md"""
当我们对一个数据结构实现了迭代器协议的时候， 我们就可以称之为一个迭代器 （Iterator)， 所有迭代器都可以丢到 `for` 循环中进行使用。

例如， 下面这个循环

```julia
for x in X
	do_something(x)
end
```

实际上等价于

```julia
next = iterate(X)
while !isnothing(next)
	i, state = next

	do_something(i)

	next = iterate(X, state)
end
```
"""

# ╔═╡ 09eaf2b7-a0b5-4455-aa4c-eb7bddb55904
md"""
下面这个 for 循环等价于
"""

# ╔═╡ 9c748ff3-2a11-4218-abb1-8bd05f86fc8f
md"""
`repeated` 迭代器可以通过以下方式进行实现
"""

# ╔═╡ 1e45ae0e-c9f9-4014-9c31-a8cd251c4abf
begin
	struct Repeated{AT}
		data::AT
		n::Int
	end
	
	Base.iterate(iter::Repeated) = (iter.data, 1)
	Base.iterate(iter::Repeated, state) = state < iter.n ? (iter.data, state+1) : nothing
end

# ╔═╡ 8a884b57-0206-4359-bfe9-80e7f44c7110
with_terminal() do
	X = [1, 2, 3]
	for X_i in Repeated(X, 2)
		println(X_i)
	end
end

# ╔═╡ e2808405-447a-4496-ab41-5bfcf42c263f
md"""
!!! note "小练习"
    利用迭代器协议实现 fibonacci 数 `f(n) = f(n-1) + f(n-2)`。 这里面需要存储的状态有几个？ 
"""

# ╔═╡ 3ff60b9e-39d8-4b51-942a-93dbb4cd2b4d
f(n) = n<=2 ? 1 : f(n-1) + f(n-2)

# ╔═╡ 46079b6d-e8a9-4482-a428-2336537d0aba
with_terminal() do
	for i in 1:5
		println(f(i))
	end
end

# ╔═╡ 60467e45-2a84-41e3-92f0-c3d4bbda8f19
md"""
## 小结

矩阵协议与迭代器协议在各种应用中都经常出现。 迭代器协议可以理解成是一类特殊的 lazy evaluation 手段： 迭代器本身并没有存储全部的数据， 而只是存储当前状态以及计算下一个状态的方法， 因此迭代器只适用于顺序读取的场景。

## 额外参考

- 关于自定义矩阵， 可以参考 [JuliaArrays](https://github.com/JuliaArrays) 中的一些实际例子
- 关于迭代器， 可以参考 [`Base.Iterators`](https://github.com/JuliaLang/julia/blob/master/base/iterators.jl) 实现以及 [IterTools.jl](https://github.com/JuliaCollections/IterTools.jl) 中的实现。
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
MappedArrays = "dbb5928d-eab1-5f90-85c2-b9b0edb7c900"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"

[compat]
BenchmarkTools = "~1.2.0"
MappedArrays = "~0.4.1"
PlutoUI = "~0.7.19"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.7.0-rc2"
manifest_format = "2.0"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "0bc60e3006ad95b4bb7497698dd7c6d649b9bc06"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.1.1"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "61adeb0823084487000600ef8b1c00cc2474cd47"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.2.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[deps.HypertextLiteral]]
git-tree-sha1 = "2b078b5a615c6c0396c77810d92ee8c6f470d238"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.3"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "8076680b162ada2a031f707ac7b4953e30667a37"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.2"

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

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.MappedArrays]]
git-tree-sha1 = "e8b359ef06ec72e8c030463fe02efe5527ee5142"
uuid = "dbb5928d-eab1-5f90-85c2-b9b0edb7c900"
version = "0.4.1"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"

[[deps.Parsers]]
deps = ["Dates"]
git-tree-sha1 = "ae4bbcadb2906ccc085cf52ac286dc1377dceccc"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.1.2"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "Dates", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "UUIDs"]
git-tree-sha1 = "e071adf21e165ea0d904b595544a8e514c8bb42c"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.19"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
"""

# ╔═╡ Cell order:
# ╠═5a829caf-fba9-483f-98a9-c30278f266c0
# ╟─c4d8eaba-44ee-11ec-21d0-0b9931dc5487
# ╟─9e816bda-81e7-4981-837d-ffa8870b8eb3
# ╟─0662c5e4-dd43-4396-bc58-9e30b9f5d85d
# ╠═690c08fd-7315-4021-b060-daba5bf7ef01
# ╠═f6720a0b-8dd9-47ce-91c3-410a67c2c93f
# ╠═3a6dc9ef-f91f-4201-b634-5d7508a03909
# ╟─00fe3392-e5ef-4dca-b7f2-41c245edbe7c
# ╠═1a4786be-f1ab-44e3-a783-b7f0407305dd
# ╠═9c1457fe-a643-4f93-9dcc-fda60b753a8d
# ╟─94e2bfab-2a42-4467-abe3-e563249bf411
# ╠═492a4fc3-7ff3-48db-939e-059157d58cf9
# ╟─bc7b8b75-0f03-4785-8842-60fc2e64c10c
# ╠═d30fb3fb-7145-4117-9d3a-3e8b0a32031f
# ╠═5cc795d9-d6e4-465e-a816-8972351f2ac8
# ╟─a6eb6c57-d6e1-4fd6-b0d0-988a9576ca50
# ╠═66b2df42-c98d-471b-b5d4-4e1ea7c3b866
# ╠═2c556187-0243-432c-924e-47289b7f0143
# ╠═94fcaf12-09ca-44c0-b1d4-5ad7198c2380
# ╠═3c4f5938-21dd-464e-9037-2203e3f75eae
# ╟─f00e6fe3-a790-4057-8032-877798d2d441
# ╟─55d4d2e9-e6cc-4f7e-8701-173c19167fd4
# ╠═b4b49b06-ea1a-422f-b430-81a5714b4993
# ╟─fad0be89-5709-41d0-b6fd-26e12f33be26
# ╠═ac26d319-e7d8-4c3a-b108-6f7648cea145
# ╟─3de702a4-93bc-41ad-a4d4-f5605d791894
# ╠═a26b7615-ee4d-44ce-8b12-346b6e438ee4
# ╠═abb1703c-221e-40f7-a1f7-2a5f4492de41
# ╟─4efbc992-9102-4a94-bb8a-29e75ac09389
# ╟─eee131cc-ed80-4b86-bcc9-5a090296a16a
# ╟─09eaf2b7-a0b5-4455-aa4c-eb7bddb55904
# ╟─9c748ff3-2a11-4218-abb1-8bd05f86fc8f
# ╠═1e45ae0e-c9f9-4014-9c31-a8cd251c4abf
# ╠═8a884b57-0206-4359-bfe9-80e7f44c7110
# ╟─e2808405-447a-4496-ab41-5bfcf42c263f
# ╠═3ff60b9e-39d8-4b51-942a-93dbb4cd2b4d
# ╠═46079b6d-e8a9-4482-a428-2336537d0aba
# ╟─60467e45-2a84-41e3-92f0-c3d4bbda8f19
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
