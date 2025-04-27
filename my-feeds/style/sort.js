// 请用以下代码替换 /data/feeds/style/sort.js 的全部内容

(function() { // 使用 IIFE 隔离作用域
    console.log("Sort script file loaded."); // <-- 日志：文件已加载

    // **等待 DOM 内容加载完毕**
    document.addEventListener('DOMContentLoaded', () => {
        console.log("DOMContentLoaded event fired. Starting sort logic."); // <-- 日志：DOM 已就绪

        // 现在尝试查找表格元素，DOM 应该已经准备好了
        const table = document.getElementById('fileTable');
        console.log("Table element found:", table); // <-- 日志：检查表格是否找到
        // 检查是否找到了表格元素
        if (!table) {
            console.log("Error: Table with ID 'fileTable' not found AFTER DOMContentLoaded."); // <-- 日志：如果还没找到，说明 HTML 有问题
            return; // 如果没找到表格，退出函数
        }

        // 查找带有 data-sort-by 属性的表头单元格
        const headers = table.querySelectorAll('thead th[data-sort-by]');
        console.log("Headers found:", headers); // <-- 日志：检查表头是否找到

        // 查找 tbody 元素
        const tbody = table.querySelector('tbody');
        console.log("Tbody found:", tbody); // <-- 日志：检查 tbody 是否找到
        // 检查是否找到了 tbody
        if (!tbody) {
            console.log("Error: Tbody element not found within the table."); // <-- 日志：如果没找到，说明 HTML 有问题
            return; // 如果没找到 tbody，退出函数
        }


        // --- 以下是核心的排序逻辑和事件监听代码，与之前相同 ---
        // 为每个可排序的表头添加点击事件监听器
        console.log("Attaching event listeners to headers...");
        headers.forEach(header => {
            console.log("Attaching listener to:", header);
            header.addEventListener('click', () => {
                console.log("Header clicked:", header);

                const sortColumn = header.dataset.sortBy;
                console.log("Sorting by column:", sortColumn);

                let sortDirection = header.dataset.sortDirection === 'asc' ? 'desc' : 'asc';
                console.log("New sort direction:", sortDirection);

                header.dataset.sortDirection = sortDirection;
                console.log("data-sort-direction set on clicked header:", header.dataset.sortDirection);

                headers.forEach(h => {
                     if (h !== header) {
                         h.dataset.sortDirection = '';
                     }
                });
                console.log("Other headers' direction attributes reset.");

                const rows = Array.from(tbody.querySelectorAll('tr'));
                console.log("Number of rows found:", rows.length);

                console.log("Starting row sorting...");
                rows.sort((rowA, rowB) => {
                    // --- Handle parent directory row ---
                    const isParentA = rowA.classList.contains('parent-dir');
                    const isParentB = rowB.classList.contains('parent-dir');

                    if (isParentA && !isParentB) return -1;
                    if (!isParentA && isParentB) return 1;
                    if (isParentA && isParentB) return 0;

                    // --- Regular row sorting ---
                    const valueA = rowA.dataset[sortColumn];
                    const valueB = rowB.dataset[sortColumn];
                    let comparison = 0;

                    if (sortColumn === 'name') {
                        const nameA = valueA.toLowerCase();
                        const nameB = valueB.toLowerCase();
                        if (nameA < nameB) comparison = -1;
                        else if (nameA > nameB) comparison = 1;
                        else comparison = 0;
                    } else if (sortColumn === 'size' || sortColumn === 'date') {
                        const numA = parseFloat(valueA);
                        const numB = parseFloat(valueB);
                        if (numA < numB) comparison = -1;
                        else if (numA > numB) comparison = 1;
                        else comparison = 0;
                    }
                    return sortDirection === 'asc' ? comparison : (comparison * -1);
                });
                console.log("Row sorting complete.");

                console.log("Clearing tbody content...");
                while (tbody.firstChild) {
                    tbody.removeChild(tbody.firstChild);
                }
                console.log("Tbody content cleared.");

                console.log("Appending sorted rows back to tbody...");
                rows.forEach(row => tbody.appendChild(row));
                console.log("Sorted rows appended.");
            });
        });
        console.log("Event listeners attached to headers.");


        // --- 页面加载完成后，触发初始排序 ---
        console.log("Attempting initial sort trigger...");
        const nameHeader = table.querySelector('thead th[data-sort-by="name"]');
        if (nameHeader) {
            console.log("File Name header found for initial sort.");
            // 触发点击事件，这将执行上面的点击监听器
            nameHeader.click();
            console.log("Initial click event triggered on File Name header.");
        } else {
            console.log("Error: File Name header not found for initial sort.");
        }

        console.log("Sort logic initialization complete.");
    }); // ** DOMContentLoaded listener 结束 **

    console.log("Sort script finished execution context setup (waiting for DOMContentLoaded)."); // <-- 日志：脚本文件执行完毕，但核心逻辑在等待 DOM 事件

})(); // IIFE 结束
