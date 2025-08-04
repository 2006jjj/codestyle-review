create procedure syn.usp_ImportFileCustomerSeasonal
	@Record_ID int
--1) Нарушен регистр as
AS
set nocount on
begin
	/* 2) Использование 2 переменные declare
	   3) Использование запятой после объявления первой переменной
	   4) При объявлении типов не рекомендуется использовать max 
	*/
	declare @RowCount int = (select count(*) from syn.SA_CustomerSeasonal)
	declare @ErrorMessage varchar(max)
	
--5) Неправильное расположение комментария
-- Проверка на корректность загрузки
	if not exists (
	--6) Неправильный отступ
	select 1
	--7) Неправильное объявление алиаса
	from syn.ImportFile as f
	where f.ID = @Record_ID
		and f.FlagLoaded = cast(1 as bit)
	)
	--8) блок begin/end не на том уровне
		begin
			set @ErrorMessage = 'Ошибка при загрузке файла, проверьте корректность данных'
	--9) Некорректное использование пустой строки
			raiserror(@ErrorMessage, 3, 1)
			return
		end

	--Чтение из слоя временных данных
	select
		c.ID as ID_dbo_Customer
		,cst.ID as ID_CustomerSystemType
		,s.ID as ID_Season
		,cast(cs.DateBegin as date) as DateBegin
		,cast(cs.DateEnd as date) as DateEnd
		,c_dist.ID as ID_dbo_CustomerDistributor
		,cast(isnull(cs.FlagActive, 0) as bit) as FlagActive
	into #CustomerSeasonal
	--10) Пропущен оператор as
	from syn.SA_CustomerSeasonal cs
		join dbo.customer as c on c.UID_DS = cs.UID_DS_Customer
			and c.ID_mapping_DataSource = 1
		join dbo.Season as s on s.Name = cs.Season
		join dbo.Customer as c_dist on c_dist.UID_DS = cs.UID_DS_CustomerDistributor
			--11) Алиаса cd нет, должно быть c_dist
			and cd.ID_mapping_DataSource = 1
		join syn.CustomerSystemType as cst on cs.CustomerSystemType = cst.Name
	where try_cast(cs.DateBegin as date) is not null
		and try_cast(cs.DateEnd as date) is not null
		and try_cast(isnull(cs.FlagActive, 0) as bit) is not null

	-- Определяем некорректные записи
	-- Добавляем причину, по которой запись считается некорректной
	select
		cs.*
		,case
			when c.ID is null then 'UID клиента отсутствует в справочнике "Клиент"'
			when c_dist.ID is null then 'UID дистрибьютора отсутствует в справочнике "Клиент"'
			when s.ID is null then 'Сезон отсутствует в справочнике "Сезон"'
			when cst.ID is null then 'Тип клиента отсутствует в справочнике "Тип клиента"'
			when try_cast(cs.DateBegin as date) is null then 'Невозможно определить Дату начала'
			when try_cast(cs.DateEnd as date) is null then 'Невозможно определить Дату окончания'
			when try_cast(isnull(cs.FlagActive, 0) as bit) is null then 'Невозможно определить Активность'
		end as Reason
	into #BadInsertedRows
	from syn.SA_CustomerSeasonal as cs
	left join dbo.Customer as c on c.UID_DS = cs.UID_DS_Customer
		and c.ID_mapping_DataSource = 1
	--12) Логические операторы должны переноситься на следующую строчку
	left join dbo.Customer as c_dist on c_dist.UID_DS = cs.UID_DS_CustomerDistributor and c_dist.ID_mapping_DataSource = 1
	left join dbo.Season as s on s.Name = cs.Season
	left join syn.CustomerSystemType as cst on cst.Name = cs.CustomerSystemType
	--13) Некорректный алиас cc и cd 
	where cc.ID is null
		or cd.ID is null
		or s.ID is null
		or cst.ID is null
		or try_cast(cs.DateBegin as date) is null
		or try_cast(cs.DateEnd as date) is null
		or try_cast(isnull(cs.FlagActive, 0) as bit) is null

	-- Обработка данных из файла
	--14) Перед названием таблицы, в которую осуществляется merge, into не указывается
	merge into syn.CustomerSeasonal as cs
	using (
		select
			cs_temp.ID_dbo_Customer
			,cs_temp.ID_CustomerSystemType
			,cs_temp.ID_Season
			,cs_temp.DateBegin
			,cs_temp.DateEnd
			,cs_temp.ID_dbo_CustomerDistributor
			,cs_temp.FlagActive
		from #CustomerSeasonal as cs_temp
	) as s on s.ID_dbo_Customer = cs.ID_dbo_Customer
		and s.ID_Season = cs.ID_Season
		and s.DateBegin = cs.DateBegin
	--15) Нарушена последовательность операторов, when всегда пишется на одной строчке с then, and должен быть выше
	--16) Не объявлен алиас t, в конструкции merge нужно использовать t для целевой таблицы и s для источника данных
	when matched
		and t.ID_CustomerSystemType <> s.ID_CustomerSystemType then
		update
		set
			ID_CustomerSystemType = s.ID_CustomerSystemType
			,DateEnd = s.DateEnd
			,ID_dbo_CustomerDistributor = s.ID_dbo_CustomerDistributor
			,FlagActive = s.FlagActive
	when not matched then
		insert (ID_dbo_Customer, ID_CustomerSystemType, ID_Season, DateBegin, DateEnd, ID_dbo_CustomerDistributor, FlagActive)
		values (s.ID_dbo_Customer, s.ID_CustomerSystemType, s.ID_Season, s.DateBegin, s.DateEnd, s.ID_dbo_CustomerDistributor, s.FlagActive)
		--17) Конструкция merge заканчивается ";"

	-- Информационное сообщение
	begin
		select @ErrorMessage = concat('Обработано строк: ', @RowCount)

		raiserror(@ErrorMessage, 1, 1)

		-- Формирование таблицы для отчетности
		select top 100
			Season as 'Сезон'
			,UID_DS_Customer as 'UID Клиента'
			,Customer as 'Клиент'
			,CustomerSystemType as 'Тип клиента'
			,UID_DS_CustomerDistributor as 'UID Дистрибьютора'
			,CustomerDistributor as 'Дистрибьютор'
			,isnull(format(try_cast(DateBegin as date), 'dd.MM.yyyy', 'ru-RU'), DateBegin) as 'Дата начала'
			,isnull(format(try_cast(DateEnd as date), 'dd.MM.yyyy', 'ru-RU'), DateEnd) as 'Дата окончания'
			,FlagActive as 'Активность'
			,Reason as 'Причина'
		from #BadInsertedRows

		return
	end

end
