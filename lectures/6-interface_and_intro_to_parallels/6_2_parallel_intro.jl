### A Pluto.jl notebook ###
# v0.17.1

using Markdown
using InteractiveUtils

# ╔═╡ 7a6a1c7c-b607-4763-a6c6-3e0b909413fc
using PlutoUI, ThreadPools, BenchmarkTools, Random

# ╔═╡ de1ae318-44fb-11ec-3d55-436fa48ea2b0
md"""
# 并行计算简介 （一）

日期： 10.14, 10.21

作者： 陈久宁

大纲:

- 异步模型
- 线程模型
- 数据竞争
- Channel 流水线模型
"""

# ╔═╡ e4509151-adb6-4e57-9ac5-befde695cbeb
md"""
## 异步模型

$(Show(MIME"image/png"(), read("tasks.png")))

任务拆解之后， 存在两种计算模式：

- 顺序模式 synchronization model: 每个子任务按照严格的顺序进行执行
- 异步模式 asynchronization model： 每个子任务的执行顺序是不确定的

$(Show(MIME"image/png"(), read("sync_async_models.png")))
"""

# ╔═╡ e19ed0da-02f1-4187-b132-e58b59ec5832
function do_task(i)
	sleep(0.001rand())
	println("task $i")
	rand(1024, 1024) * rand(1024, 2048) # takes about 0.1s
end

# ╔═╡ 0d957faf-bb48-4ec4-a0d7-8aaf185f72fb
md"""
下面是典型的顺序执行模式
"""

# ╔═╡ 1ad78d5b-37c2-4bbd-9771-e04168b2053e
with_terminal() do
	@time begin
		for i in 1:10
			do_task(i)
		end
	end
end

# ╔═╡ 64dade41-66a3-4949-aa62-1de24a13c746
md"""
异步执行模式可以通过 `@sync` 与 `@async` 接口实现

- `@async begin ... end` 标记的代码块会作为一个异步任务提交给任务池， 然后由具体的任务调度器来决定执行和中断
- `@sync begin ... end` 表示等待代码块中所有的异步任务结束之后才结束
"""

# ╔═╡ e8902572-cd11-427a-b1ea-977b31117720
with_terminal() do
	@time begin
		@sync for i in 1:10
			@async do_task(i)
		end
	end
end

# ╔═╡ 7b9f1fb0-f052-47fc-97cb-41f3bcde4b5e
md"""
异步模式下， 虽然任务是按顺序(for循环)创建的， 但是具体的执行顺序由任务调度器来决定。 异步与同步模型只会影响任务的执行和中断。
"""

# ╔═╡ f99ba193-9c5e-47c1-ad1d-a55874849d77
md"""
下面这段代码因为缺少 `@sync` 标记， 因此在 `@time` 记录的实际上是 10 个异步任务创建的时间。
"""

# ╔═╡ 66f6d74d-2d2b-4177-956f-f95338e73b92
with_terminal() do
	@time begin
		for i in 1:10
			@async do_task(i)
		end
	end
end

# ╔═╡ cef03d98-d21f-462e-8516-19302fd68e23
md"""
`@async` 内部依然是顺序执行。 例如下面的代码中， 任务 4 总是在任务 3 执行后才会执行。
"""

# ╔═╡ bd9c3a81-6612-4a19-bd22-860cbe0c3d53
with_terminal() do
	@time begin
		@sync for i in 1:5
			@async begin
				do_task(2i-1)
				do_task(2i)
			end
		end
	end
end

# ╔═╡ 3c5edb3d-957c-460f-b159-76d7d00bbe2c
md"""
### 异步 IO

IO(input/output) 是一类非常特殊的操作： 它们实际上并没有占用多少 CPU 资源， 而是占用其他硬件设备， 比如硬盘、 键盘、 网络以及 `sleep`。 对于这类任务来说， 调度器会将 CPU 资源转移给其他任务， 从而让总的执行时间变得更短。

$(Show(MIME"image/png"(), read("async_io.png")))
"""

# ╔═╡ 246ee1e3-4048-46e2-af83-a4894e5bd738
function do_task2(i)
	sleep(0.1rand())
	println("task $i")
	sleep(0.1rand())
end

# ╔═╡ 472f058d-412f-4762-820e-0ccc19a0db38
with_terminal() do
	@time begin
		for i in 1:10
			do_task2(i)
		end
	end
end

# ╔═╡ 0172cb68-4e63-42b1-b640-0070fc0c07ea
with_terminal() do
	@time begin
		@sync for i in 1:10
			@async do_task2(i)
		end
	end
end

# ╔═╡ 57c96e13-27be-42bd-b126-f88f48830a21
md"""
### 任务模型

`@sync` 与 `@async` 提供的是一套比较方便的 API， 它们的底层由由任务 (Task) 以及任务池 (task pool) 的概念组成。 下面介绍的是稍微底层一些的基于 Task 的 API. （当然更底层的话， Task 是基于 `yieldto` API 实现的， 不过大部分时候我们并不需要使用到它。）
"""

# ╔═╡ 0ba174f2-7c78-4bde-a263-c209012b289d
with_terminal() do
	t = @async sleep(0.1)
	@show t
	sleep(0.1)
	@show t
end

# ╔═╡ 32eedecd-55de-4528-b33f-5423387ade29
md"""
当使用 `@async` 的时候， 实际上进行了三步操作：

- 创建任务 `Task`/`@task`
- 将任务添加到任务池: `schedule`
- 让任务调度器进行任务切换: `yield`/`yieldto`
"""

# ╔═╡ 6bcd84aa-be9f-4dd3-8705-39d32d920712
with_terminal() do
	# 创建任务 t
	t = @task do_task(1)
	@show t
	@show istaskstarted(t)
	# 将任务 t 添加到任务池, 此时调度器还在执行主程序 `schedule(t)`， 并没有开始任务 t
	schedule(t)
	@show istaskstarted(t)
	yield() # 告诉调度器进行任务切换: 从任务池中选择一个可以开始的任务 （并不一定是 t )
	@show istaskstarted(t)
	@show istaskdone(t)
	wait(t) # 等待任务 t 执行结束
	@show istaskdone(t)
end

# ╔═╡ 2bc21afc-0b14-4361-847c-e2618a300f3e
md"""
任务池可以是很简单的列表， 例如：
"""

# ╔═╡ 8ef9077a-296c-421a-abd7-e1392ec85718
with_terminal() do
	# 这大致等价于前面的 `@sync`-`@async` 版本
	@time begin
		taskpool = []
		for i in 1:10
			t = @async do_task2(i)
			push!(taskpool, t)
		end

		foreach(wait, taskpool)
	end
end

# ╔═╡ 95d69b70-d618-480d-9284-987101d79cd4
md"""
小结：

- 异步模型将任务的创建和任务的执行拆分开， 从而允许操作系统进行更灵活的任务执行来降低 IO 导致的时间开销
- 异步模型仅仅只是打算任务的执行顺序， 因此对于 CPU 密集型的任务来说并不会加快执行
"""

# ╔═╡ 473e1bc1-6958-482e-b0f7-82337a990983
md"""
## 多线程模型

多线程模型引入了更多的 CPU 资源， 因此可以加速 CPU 密集型任务

$(Show(MIME"image/png"(), read("multi_threads.png")))
"""

# ╔═╡ 21375517-f55e-4cbb-af6a-4a0215d5382a
md"""
当我们打开一个 Julia 程序的时候， 我们创建了一个 Julia 进程 (Process), 一个 Julia 进程可能含有多个线程 (Thread)。 进程(Process)之间是相互独立的， 线程(Thread)则会共享进程的内存数据。

$(Show(MIME"image/png"(), read("thread_model.png")))
"""

# ╔═╡ bc856a18-c980-44ad-bbb8-7b0f5fd60893
md"""
!!! note "设定与查看线程数"
	线程数的设定必须在打开 Julia 之前进行， 通过设定环境变量 `JULIA_NUM_THREADS` 来得到。 例如在 Linux Bash 下， `JULIA_NUM_THREADS=8 julia` 会创建 8 个线程。 关于其他系统和命令行， 网上可以找到非常多的关于“环境变量”的参考材料， 因此这里不多加解释。 

	可以通过 `Threads.nthreads()` 查看线程数目， 也可以通过 `versioninfo()` 查看与 Julia 有关的环境变量。
"""

# ╔═╡ 95efe7ba-d78d-4d26-8023-8236a4d256d8
with_terminal() do
	@show Threads.nthreads()
	versioninfo()
end

# ╔═╡ 1ad22cc7-f697-4e47-8d9e-c282833f0dfc
md"""
!!! note "超线程 Hyper-threading"
	一般来说， 每一个线程的计算资源是独立的， [超线程](https://en.wikipedia.org/wiki/Hyper-threading)是指在一个CPU核心(Core)上构造出的多个虚拟核心(一般是两个)。 比如说 "Intel i9-9900K 是 8核16线程" 实际上指的是8个CPU核心， 每个核心虚拟出了两个线程资源。
    对于高性能计算任务来说， 计算资源的共享会在一定程度上增加上下文切换的开销， 从而降低计算效率， 因此一般来说数值计算中只使用真实物理核心数目的线程数量。
"""

# ╔═╡ 991c4473-b224-4436-90c2-a37eab6bc66f
function do_cpu_task(i)
	sleep(0.001rand())
	println("Thread $(Threads.threadid()): task $(i)")
	rand(1024, 1024) * rand(1024, 2048) # takes about 0.1s
end

# ╔═╡ 56a06db8-a9e3-4d94-860f-b94739e0358a
with_terminal() do
	@time begin
		Threads.@threads for i in 1:8
			do_cpu_task(i)
		end
	end
end

# ╔═╡ 408ad69c-670e-4e37-a152-6f44b3f7eb05
md"""
多线程也可以直接使用对应的底层 Task 模型来实现： 与单线程异步模型中唯一有差别是将任务分配空余的线程上。
"""

# ╔═╡ 3f2a4597-fbaa-49ff-ab46-ca62f298ae72
md"""
**单线程异步模型**：

CPU 密集型任务， 因此单线程异步并不会让代码执行的更快。
"""

# ╔═╡ d81c2b99-4723-47da-9f89-812409056047
with_terminal() do
	@time begin
		taskpool = [@async do_cpu_task(i) for i in 1:10]
		foreach(wait, taskpool)
	end
end

# ╔═╡ 6481965e-6d59-400c-8c06-ee5efc83c409
md"""
**多线程异步模型**：

!!! note "`@spawn` 与 `@async`"
	`Threads.@spawn` 会将创建好的任务分配到空闲的线程(Thread)上， 而 `@async` 则是分配到空余的协程(coroutine)上。 简单来说， 协程是由 Julia （或其他用户程序） 创建的用户态进程， 它提供了上下文切换的异步功能（concurrency）， 但是并不能调用 CPU 的多核资源 （因为这些协程实际上共享同一个系统线程）。
"""

# ╔═╡ f2da005b-a6b4-42b1-820a-66f08842175d
with_terminal() do
	@time begin
		taskpool = [Threads.@spawn do_cpu_task(i) for i in 1:10]
		foreach(wait, taskpool)
	end
end

# ╔═╡ bd423a90-eef8-407c-9fa8-8951ead4d01e
md"""
## 数据竞争与锁 data races and locks

前面关于线程模型我们知道同一个进程下的各个线程之间是会共享内存数据的， 因此当不同的线程试图去修改内存数据的时候， 就会发生数据竞争的情况。 数据竞争只发生在写入的时候而不会发生在读取的时候。
"""

# ╔═╡ df28487a-96ac-435e-8675-eb9d0396a41b
md"""
为了演示数据竞争， 我们使用一个简单的求和的例子：
"""

# ╔═╡ b662272a-15b7-41cf-8558-0dbfac9af6ac
sum(x->x*x, 1:10000)

# ╔═╡ 9696e2c5-64b3-4f9a-bcb3-da1bd9a1577c
md"""
使用多线程之后， 结果变得不对了， 而且每次运行的结果都不一样。
"""

# ╔═╡ 3f9f7716-aec3-40d1-baf4-2758f392c376
let X = 1:10000
	rst = 0
	Threads.@threads for x in X
		rst += x * x
	end
	rst
end

# ╔═╡ a1d59c26-36bf-47bc-8042-8eb289819878
md"""
为什么使用多线程会导致结果变得更小了？ 简单来说， 就是其他线程计算的结果被一个旧的数据给覆盖了。

$(Show(MIME"image/png"(), read("data_races.png")))
"""

# ╔═╡ 471121ab-9bbb-438e-8281-46d74877cce8
md"""
解决数据竞争的核心思路是避免同时写入， 操作起来有两种一般手段：

- 加锁
- 避免数据共享
"""

# ╔═╡ d4f2b519-b936-4339-864e-ed7b51e76163
md"""
### 加锁
"""

# ╔═╡ 73dde19d-d9c3-4a9e-8dbc-1b2e33abd716
md"""
锁的本质是将异步任务转换成同步的串行任务： 由各个线程排队来使用一个公共资源。

设想一下超市购物的场景： 一群人去超市购物， 购物完之后排队买单， 买单完之后由各自离去。 如果我们说每个单独的人是一个线程的时候， 那么购物这件事情就是一个并行的异步活动， 排队买单则强制性地将异步活动转换成了同步的串行活动， 买完单之后又恢复到异步活动。
"""

# ╔═╡ d4c07006-e317-4982-b7f4-7943c8a9d281
md"""
例如， 我们知道下面这个并行任务只需要花 0.5 s左右就可以结束。
"""

# ╔═╡ 921c9693-5327-41b5-8b20-659672b702c1
with_terminal() do
	@time begin
		@sync begin
			Threads.@spawn begin
				println("Thread id: ", Threads.threadid())
				sleep(0.5+0.1rand())
				println("Do task 1")
			end
			Threads.@spawn begin
				println("Thread id: ", Threads.threadid())
				sleep(0.5+0.1rand())
				println("Do task 2")
			end
		end
	end
	nothing
end

# ╔═╡ a5087f23-b729-468f-9d74-a67a9eaed652
md"""
加锁的话则是通过 `lock`/`unlock` 来实现. 关于下面代码的结果有两个值得注意的地方：

- 其他任务的开始一定发生在拿到锁之后才进行： 例如这里打印第二个 thread id 一定发生在打印完第一个 do task之后。
- 因此， 虽然表面上我们使用 `@spawn`/`@sync` 将任务并行化了， 但是由于锁的存在， 任务本质上还是以串行的方式在执行。
"""

# ╔═╡ 6dcf0b85-272c-4970-be3a-ea17a4e10390
with_terminal() do
	l = ReentrantLock()
	@time begin
		@sync begin
			Threads.@spawn begin
				println("spawn task 1")
				lock(l)
				println("Thread id: ", Threads.threadid())
				sleep(0.5+0.1rand())
				println("Do task 1")
				unlock(l)
			end
			Threads.@spawn begin
				println("spawn task 2")
				lock(l)
				println("Thread id: ", Threads.threadid())
				sleep(0.5+0.1rand())
				println("Do task 2")
				unlock(l)
			end
		end
	end
	nothing
end

# ╔═╡ bc355e91-e80e-48b5-a401-b5ce56c8d0ca
md"""
常见的锁有两种类型：

- `Threads.SpinLock()`: 同一时刻只能有一个任务占有它 `lock`， 当另一个任务试图去占有的话， 一定会先等待任务结束（`unlock`)。 这种锁是严格互斥的。
- `Threads.ReentrantLock()`: 单个 Task 内允许多次占用， 不同线程之间会互斥.

!!! tip "大多数时候， 直接使用 `ReentrantLock`"
	Spin lock 是一种非常简单的锁机制， 在预期锁很快就会释放的时候性能会更好， 因为不会涉及到系统调用， 也不存在上下文切换。 但是因为 Spin lock 的互斥条件更严格， 所以很容易导致其他线程在不需要被等待的时候因为互斥条件一直处于尝试获取锁的状态 (spin)， 从而导致整体的性能变差。 从易用性的角度来说， 使用 `ReentrantLock` 是一个非常方便的解决方案； 使用 `SpinLock` 只有在确实证明在各种情况下都有性能提升的时候才应该使用。

	参考 [Wikipedia: Spinlock](https://en.wikipedia.org/wiki/Spinlock)
"""

# ╔═╡ 5a76eac3-2ac5-4ce7-aa18-0be463089e1c
md"""
`lock` 会锁死当前资源， 因此如果忘记 `unlock` 的话， 则程序的执行会因为互斥条件卡住， 比如说下面这种：

```julia
l = Threads.SpinLock()
lock(l)
println("lock for the first time")
lock(l) # hangs permanently
println("lock for the second time")
```

因此一个最佳实践是使用 `lock` 的 `do` 语法:

```julia
lock(l) do
	do_something()
end
```

这背后等价于

```julia
lock(l)
try
    do_something()
finally
    unlock(l)
end
```
"""

# ╔═╡ ac114867-a213-4339-89c4-c0576de25fd2
md"""
回到上面的小例子， 我们可以重写为：
"""

# ╔═╡ 851f6e76-6307-4458-99e5-dc356e90e171
function threaded_sum_lock(X)
	l = ReentrantLock()
	rst = 0
	Threads.@threads for x in X
		tmp = x*x # 并行
		lock(l) do
			# 因为加锁变成了串行模型
			rst += tmp
		end
	end
	rst
end

# ╔═╡ 53e93a70-9303-4f98-b5a6-a549558ed05e
with_terminal() do
	X = 1:10000
	rst_sync = @btime sum(x->x*x, $X)
	rst_threaded_lock = @btime threaded_sum_lock($X)
	rst_sync == rst_threaded_lock
end

# ╔═╡ 20b56c58-0165-4cd1-abe0-30c777b704bd
md"""
当问题规模太小的时候， 并行和加锁本身的开销远远超出了实际计算的开销。
"""

# ╔═╡ bf03636f-29ff-4baa-9268-901e6969b5af
md"""
### 使用线程上下文来避免数据共享

除去加锁这个将任务强制串行的方法以外， 我们还可以通过每个线程独享一个 `rst` 变量的方式来解决数据竞争的问题， 但同时每个任务依然还是并行的模式在计算。
"""

# ╔═╡ f99a4d41-4417-4799-a6bc-11c643889321
function threaded_sum_thread_status(X)
	# 每个线程存储一个 rst 状态
	rst = [zero(eltype(X)) for _ in 1:Threads.nthreads()]
	Threads.@threads for x in X
		tmp = x * x
		rst[Threads.threadid()] += tmp
	end
	# 等所有子任务都进行完之后， 再利用一个单线程来计算出最终结果
	sum(rst)
end

# ╔═╡ 0a6932d0-2cd4-44c1-b8dd-f3594064cb07
md"""
对于这个非常简单的小任务来说， 虽然还是比串行的模式要慢， 但是比加锁的模式要快
"""

# ╔═╡ 9cb07a37-b9ca-4bfa-8f39-e794e5189d25
with_terminal() do
	X = 1:10000
	rst_sync = @btime sum(x->x*x, $X)
	rst_threaded = @btime threaded_sum_thread_status($X)
	rst_sync == rst_threaded
end

# ╔═╡ 99d635d9-2937-4e03-bf9c-43ae25236bef
md"""
## 任务的分配

每个子任务的计算规模可能是不同的， 简单的理想情况下会假设每个子任务的计算时间基本一致， 从而将任务均匀地分配到不同的线程上。 `Threads.@threads` 假设的是均匀任务， 对于不均匀任务来说， [ThreadPools](https://github.com/tro3/ThreadPools.jl) 提供了一些非常方便的调度器。

实际上， 前面介绍的 `@sync`-`Threads.@spawn` 其实就挺好用的了。
"""

# ╔═╡ eaba16eb-64d4-42dc-a260-c1507f7966d7
function do_cpu_task2(i)
	sleep(0.001rand())
	rand(1024, 1024) * rand(1024, 2048) # takes about 0.1s
	# 每个任务的时间开销并不相同
	sleep(0.1i)
end

# ╔═╡ 3e3c7a67-82ea-4b6f-ab1a-c4be3cd0c355
with_terminal() do
	@time begin
		Threads.@threads for i in 1:4Threads.nthreads()
			do_cpu_task2(i)
		end
	end

	@time begin
		ThreadPools.@qthreads for i in 1:4Threads.nthreads()
			do_cpu_task2(i)
		end
	end
	nothing
end

# ╔═╡ 67e263f5-664d-4419-8ff4-8dd1a11c7c4d
md"""
## Channel 模型

在做深度学习任务或者的时候， 经常会遇到以下的流水线模型：

- 数据读取， 因为主要是 IO 操作， 所以使用异步模型即可
- 数据预处理， 将读取进来的数据转换成网络的输入。 这一般使用 CPU 进行多线程/进程运算。
- 网络训练， 主要是 GPU 运算

下面这种代码的计算效率并不是最高的： 当某个线程处于前一环节时， 后面的环节的资源没有被利用到。

```julia
for i in tasks
    data = load_data(i)
    X, Y = process(data)
    train_network(X, Y)
end
```
"""

# ╔═╡ 4a61fbbe-822c-453f-beb6-13c0a351cf21
md"""
假设下面是我们简单的数据处理流水线

$(Show(MIME"image/png"(), read("naive_pipeline.png")))
"""

# ╔═╡ edafe8d2-8abc-48f0-8ee5-49f3a4fcf137
function load_data(i)
	# 使用 sleep 来模拟 IO 开销
	sleep(0.2)
	X = rand(Random.MersenneTwister(i), 1024, 1024)
	print("-")
	return X
end

# ╔═╡ 70087d8e-22a6-439e-83d0-13f3962ebe69
function process_data(X)
	Y = sum(@. abs(X*X*X - 0.5))
	print(".")
	return Y
end

# ╔═╡ 234767b7-cb09-484d-9b6a-dab740fceb74
function pipeline_single_thread()
	rst = 0
	for i in 1:4Threads.nthreads()
		X = load_data(i)
		rst += process_data(X)
	end
	return rst
end

# ╔═╡ 2f5e4954-8be2-4711-9b39-ce61b39d2ba8
function pipeline_plain_threads()
	rst = 0
	l = ReentrantLock()
	Threads.@threads for i in 1:4Threads.nthreads()
		X = load_data(i)
		tmp = process_data(X)
		lock(l) do
			rst += tmp
		end
	end
	rst
end

# ╔═╡ 92cac291-c15e-4821-983c-bf0f4882e18b
md"""
虽然并行计算能够让代码变得更快， 但是在每一个线程中， `process_data` 必须要等待 `load_data` 完成才会开始工作， 这其实就导致计算资源在进行不必要的等待。
"""

# ╔═╡ fc5eed78-34b6-4291-a322-3d58572939ab
with_terminal() do
	r1 = @time pipeline_single_thread()
	r2 = @time pipeline_plain_threads()
	r1 ≈ r2
end

# ╔═╡ ab4d1ba2-d60e-471f-ac09-d6e15065ab21
md"""
Channel 模型是一个很简单的优化这类流水线模型的一个思路: 流水线前一个阶段的所有输出全部丢进 Channel 中， 然后后一个阶段则从 Channel 中获取数据。 这样做的好处可以让每个阶段都保持繁忙。

$(Show(MIME"image/png"(), read("channel_model.png")))

"""

# ╔═╡ a5487257-2429-40d0-874e-48f7ca975feb
md"""
`Channel` 是一个非常简单的 FIFO (first-in-first-out) 数据结构， 通过 `put!` 与 `take!` 来添加与获取数据。
"""

# ╔═╡ 30644964-3f9a-4a9e-be9c-056e3c65f235
with_terminal() do
	# 这个管道最多同时存放 4 个数据
	ch = Channel(4)
	put!(ch, 0)
	put!(ch, 1)
	@show take!(ch)
	@show take!(ch)
end

# ╔═╡ be2a82e1-eca7-4911-b52c-cde5b624432b
md"""
`Channel` 也接受函数形式的输入， 来构造一个类似于生成器的对象
"""

# ╔═╡ d58b418a-553a-4f25-b304-3392568e4757
with_terminal() do
	ch = Channel() do ch
		for i in 1:4
			put!(ch, 2i)
		end
	end

	for x in ch
		@show x
	end
end

# ╔═╡ dacc9631-3688-4e83-bac4-d2089a0d54be
md"""
存在两种极端情况：

- 当管道中没有数据时， `take!` 会进入到等待模式， 直到下一个 `put!` 运算进来。
- 当管道中缓存已经装满了数据时， `put!` 会进入到等待模式， 直到有一个 `take!` 操作试图获取数据。 默认情况下 `Channel()` 的缓存大小为 `0`， 即没有缓存。
"""

# ╔═╡ 248fb34c-36bc-4d96-81c2-3b04c216279e
with_terminal() do
	ch = Channel()
	@async begin
		sleep(0.2)
		put!(ch, nothing)
	end
	# 因为 put! 延迟了 0.2s， 所以 take! 需要等待 0.2s 才能执行完
	@time take!(ch)
end

# ╔═╡ e86e8016-3767-4a81-8375-911596bb12b6
with_terminal() do
	ch = Channel()
	@async begin
		sleep(0.2)
		take!(ch)
	end
	# 因为 take! 延迟了 0.2s， 所以 put! 需要等待 0.2s 才能执行完
	@time put!(ch, nothing)
end

# ╔═╡ facd655b-2f52-4de5-ac43-d5d934d2ca30
md"""
如果想要使用多线程的话， 那么就可以将 Channel 的生成函数构造成多线程的模式.
"""

# ╔═╡ 0bd918d4-b3aa-4da0-8017-96a0a6566544
with_terminal() do
	@time begin
		ch = Channel(4) do ch
			@sync for i in 1:8
				Threads.@spawn put!(ch, do_cpu_task(i))
			end
		end
		for x in ch end
	end
end

# ╔═╡ c05d99b3-ff3d-42e7-978c-884c667fceaa
md"""
现在将前面的流水线例子用 `Channel` 重写一遍则是:
"""

# ╔═╡ e0778a69-878e-4f0e-8a04-13a03de9dde1
function pipeline_channel_threads()
	ch = Channel(Threads.nthreads()) do ch
		@sync for i in 1:4Threads.nthreads()
			@async put!(ch, load_data(i))
		end
	end

	rst = 0
	l = ReentrantLock()
	@sync for X in ch
		Threads.@spawn begin
			tmp = process_data(X)
			lock(l) do
				rst += tmp
			end
		end
	end
	return rst
end

# ╔═╡ ff93f1bc-cba9-4252-a527-d12c865631c6
with_terminal() do
	r1 = @time pipeline_plain_threads()
	r2 = @time pipeline_channel_threads()
	r1 ≈ r2
end

# ╔═╡ 3e5b8adf-4421-4d3e-8bfd-e6495dc40dc7
md"""
可以看到， 通过引入 Channel 的概念， 可以让整个流水线的各个环节尽可能地不等待其他环节的结果， 从而进一步提高整体的效率。 

!!! note "避免资源抢占"
	这个加速策略的有效性是有前提的， 即流水线的不同环节不存在资源的抢占： 包括计算资源（CPU、GPU、内存） 以及 IO 资源（磁盘、 网络）。

	我们这里构造的例子中， 第一阶段主要涉及的是异步 IO 操作， 而第二个阶段主要是 CPU 计算， 因此每个阶段都可以保持繁忙的计算， 并且不会因为资源抢占导致效率降低。
"""

# ╔═╡ e8206fd6-faed-4128-ba80-c557687e43cf
md"""
除了上面提到的基于生成函数的 Channel 用法以外， 实际上也可以直接从多个线程中手动 `put!`
"""

# ╔═╡ e1cda401-d419-4055-a269-ce8b174c5b90
with_terminal() do
	ch = Channel(4)

	@async for x in ch
		sleep(0.01)
	end

	@time begin
		Threads.@threads for t in 1:10
			put!(ch, do_cpu_task(t))
		end
	end
end

# ╔═╡ 80ba49f3-6299-437f-aa97-41bcc32d7b4c
md"""
!!! warning "多线程并不必然会使代码变得更快"
	多线程的内存数据是共享的， 因此如果子任务涉及到大量内存开销时， GC 操作会将全部线程都暂停。 在这种情况下， 多进程的模式因为每个进程的内存是互相独立的， 受到 GC 的影响会更小一些。
	
	在使用多线程策略之前， 首先需要确保在单线程上没有什么可疑的性能问题， 例如： 类型不稳定、 不必要的内存开销， 等等。 否则的话加上多线程很可能代码会变得更慢。
"""

# ╔═╡ d3c288ce-800f-416e-a5a0-dc15cffca992
md"""
### Summary

在介绍并行计算之前， 我们先介绍了异步计算的概念， 异步计算通过将任务拆解成顺序无关的一些子任务， 从而允许多个 worker 来同时执行这些子任务。 不同硬件层级上的 worker 就引入了不同的并行计算模式：

- CPU level： 单指令多数据流， 常见的有 [SIMD](https://en.wikipedia.org/wiki/SIMD) 与 [AVX](https://en.wikipedia.org/wiki/Advanced_Vector_Extensions)。 这种并行非常高效， 但是只针对非常有限的基本指令操作。
- Thread level: 线程是执行计算任务的操作系统级别的最小单元， 线程本身并不包含内存数据， 而是共享进程的内存。
- Process level: 一个进程可以包含有一个或多个线程， 进程有独立的内存空间， 不与其他进程共享。 因为不共享数据， 进程级别的并行计算需要引入进程间的通讯机制。
- Machine level: 这里的机器可以指单个 CPU， 也可以指单个物理机。 因为机器级别的通讯一般通过总线或者网线连接， 这个规模的并行一般称之为分布式计算 distributed computing。

在这一节里我们介绍了最简单的线程级别的并行， 因为同一个进程下的多个线程会共享内存数据， 因此在写多线程算法时会涉及到数据竞争的问题

- 数据竞争的原因是因为同时对一个共享的数据进行了写入操作
- 解决数据竞争的思路是避免同时写入， 常用的方式有两种：
  - 加锁： 锁的本质是将并行任务串行化
  - 引入线程状态来避免全局的写入操作： 一般来说比加锁的并行效率要更高， 但是并不是所有算法都能够这样做

我们还介绍了多线程模型的一个简单的基于 `Channel` 的流水线模型： 通过让流水线的每个环节相对独立且相对繁忙， 来减少闲置资源， 并进一步加速整体的计算效率。
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
ThreadPools = "b189fb0b-2eb5-4ed4-bc0c-d34c51242431"

[compat]
BenchmarkTools = "~1.2.0"
PlutoUI = "~0.7.19"
ThreadPools = "~2.1.0"
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

[[deps.RecipesBase]]
git-tree-sha1 = "44a75aa7a527910ee3d1751d1f0e4148698add9e"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.1.2"

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

[[deps.ThreadPools]]
deps = ["Printf", "RecipesBase", "Statistics"]
git-tree-sha1 = "bd6b4d20ebf046ec9dcc6d9e6643b72b60d1d52c"
uuid = "b189fb0b-2eb5-4ed4-bc0c-d34c51242431"
version = "2.1.0"

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
# ╠═7a6a1c7c-b607-4763-a6c6-3e0b909413fc
# ╟─de1ae318-44fb-11ec-3d55-436fa48ea2b0
# ╟─e4509151-adb6-4e57-9ac5-befde695cbeb
# ╠═e19ed0da-02f1-4187-b132-e58b59ec5832
# ╟─0d957faf-bb48-4ec4-a0d7-8aaf185f72fb
# ╠═1ad78d5b-37c2-4bbd-9771-e04168b2053e
# ╟─64dade41-66a3-4949-aa62-1de24a13c746
# ╠═e8902572-cd11-427a-b1ea-977b31117720
# ╟─7b9f1fb0-f052-47fc-97cb-41f3bcde4b5e
# ╟─f99ba193-9c5e-47c1-ad1d-a55874849d77
# ╠═66f6d74d-2d2b-4177-956f-f95338e73b92
# ╟─cef03d98-d21f-462e-8516-19302fd68e23
# ╠═bd9c3a81-6612-4a19-bd22-860cbe0c3d53
# ╟─3c5edb3d-957c-460f-b159-76d7d00bbe2c
# ╠═246ee1e3-4048-46e2-af83-a4894e5bd738
# ╠═472f058d-412f-4762-820e-0ccc19a0db38
# ╠═0172cb68-4e63-42b1-b640-0070fc0c07ea
# ╟─57c96e13-27be-42bd-b126-f88f48830a21
# ╠═0ba174f2-7c78-4bde-a263-c209012b289d
# ╟─32eedecd-55de-4528-b33f-5423387ade29
# ╠═6bcd84aa-be9f-4dd3-8705-39d32d920712
# ╟─2bc21afc-0b14-4361-847c-e2618a300f3e
# ╠═8ef9077a-296c-421a-abd7-e1392ec85718
# ╟─95d69b70-d618-480d-9284-987101d79cd4
# ╟─473e1bc1-6958-482e-b0f7-82337a990983
# ╟─21375517-f55e-4cbb-af6a-4a0215d5382a
# ╟─bc856a18-c980-44ad-bbb8-7b0f5fd60893
# ╠═95efe7ba-d78d-4d26-8023-8236a4d256d8
# ╟─1ad22cc7-f697-4e47-8d9e-c282833f0dfc
# ╠═991c4473-b224-4436-90c2-a37eab6bc66f
# ╠═56a06db8-a9e3-4d94-860f-b94739e0358a
# ╟─408ad69c-670e-4e37-a152-6f44b3f7eb05
# ╟─3f2a4597-fbaa-49ff-ab46-ca62f298ae72
# ╠═d81c2b99-4723-47da-9f89-812409056047
# ╟─6481965e-6d59-400c-8c06-ee5efc83c409
# ╠═f2da005b-a6b4-42b1-820a-66f08842175d
# ╟─bd423a90-eef8-407c-9fa8-8951ead4d01e
# ╟─df28487a-96ac-435e-8675-eb9d0396a41b
# ╠═b662272a-15b7-41cf-8558-0dbfac9af6ac
# ╟─9696e2c5-64b3-4f9a-bcb3-da1bd9a1577c
# ╠═3f9f7716-aec3-40d1-baf4-2758f392c376
# ╟─a1d59c26-36bf-47bc-8042-8eb289819878
# ╟─471121ab-9bbb-438e-8281-46d74877cce8
# ╟─d4f2b519-b936-4339-864e-ed7b51e76163
# ╟─73dde19d-d9c3-4a9e-8dbc-1b2e33abd716
# ╟─d4c07006-e317-4982-b7f4-7943c8a9d281
# ╠═921c9693-5327-41b5-8b20-659672b702c1
# ╟─a5087f23-b729-468f-9d74-a67a9eaed652
# ╠═6dcf0b85-272c-4970-be3a-ea17a4e10390
# ╟─bc355e91-e80e-48b5-a401-b5ce56c8d0ca
# ╟─5a76eac3-2ac5-4ce7-aa18-0be463089e1c
# ╟─ac114867-a213-4339-89c4-c0576de25fd2
# ╠═851f6e76-6307-4458-99e5-dc356e90e171
# ╠═53e93a70-9303-4f98-b5a6-a549558ed05e
# ╟─20b56c58-0165-4cd1-abe0-30c777b704bd
# ╟─bf03636f-29ff-4baa-9268-901e6969b5af
# ╠═f99a4d41-4417-4799-a6bc-11c643889321
# ╟─0a6932d0-2cd4-44c1-b8dd-f3594064cb07
# ╠═9cb07a37-b9ca-4bfa-8f39-e794e5189d25
# ╟─99d635d9-2937-4e03-bf9c-43ae25236bef
# ╠═eaba16eb-64d4-42dc-a260-c1507f7966d7
# ╠═3e3c7a67-82ea-4b6f-ab1a-c4be3cd0c355
# ╟─67e263f5-664d-4419-8ff4-8dd1a11c7c4d
# ╟─4a61fbbe-822c-453f-beb6-13c0a351cf21
# ╠═edafe8d2-8abc-48f0-8ee5-49f3a4fcf137
# ╠═70087d8e-22a6-439e-83d0-13f3962ebe69
# ╠═234767b7-cb09-484d-9b6a-dab740fceb74
# ╠═2f5e4954-8be2-4711-9b39-ce61b39d2ba8
# ╟─92cac291-c15e-4821-983c-bf0f4882e18b
# ╠═fc5eed78-34b6-4291-a322-3d58572939ab
# ╟─ab4d1ba2-d60e-471f-ac09-d6e15065ab21
# ╟─a5487257-2429-40d0-874e-48f7ca975feb
# ╠═30644964-3f9a-4a9e-be9c-056e3c65f235
# ╟─be2a82e1-eca7-4911-b52c-cde5b624432b
# ╠═d58b418a-553a-4f25-b304-3392568e4757
# ╟─dacc9631-3688-4e83-bac4-d2089a0d54be
# ╠═248fb34c-36bc-4d96-81c2-3b04c216279e
# ╠═e86e8016-3767-4a81-8375-911596bb12b6
# ╟─facd655b-2f52-4de5-ac43-d5d934d2ca30
# ╠═0bd918d4-b3aa-4da0-8017-96a0a6566544
# ╟─c05d99b3-ff3d-42e7-978c-884c667fceaa
# ╠═e0778a69-878e-4f0e-8a04-13a03de9dde1
# ╠═ff93f1bc-cba9-4252-a527-d12c865631c6
# ╟─3e5b8adf-4421-4d3e-8bfd-e6495dc40dc7
# ╟─e8206fd6-faed-4128-ba80-c557687e43cf
# ╟─e1cda401-d419-4055-a269-ce8b174c5b90
# ╟─80ba49f3-6299-437f-aa97-41bcc32d7b4c
# ╟─d3c288ce-800f-416e-a5a0-dc15cffca992
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
