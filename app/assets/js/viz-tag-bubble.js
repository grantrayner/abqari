// Tag Bubble — circle pack of tags sized by post count.
// Loads /visualizations/tag-bubble.json (pre-built at site build time)
// and renders into #viz-container. Colors come from a fixed palette;
// stroke and text use currentColor so light/dark themes flow through.
(function () {
  'use strict';

  var PALETTE = ['#4e79a7', '#f28e2b', '#e15759', '#76b7b2', '#59a14f',
                 '#edc948', '#b07aa1', '#ff9da7', '#9c755f', '#bab0ac',
                 '#d37295', '#fabfd2'];

  document.addEventListener('DOMContentLoaded', function () {
    var container = document.getElementById('viz-container');
    var loading = document.getElementById('viz-loading');
    var tooltip = document.getElementById('viz-tooltip');
    if (!container) return;

    fetch('/visualizations/tag-bubble.json', { cache: 'no-cache' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (data) { render(data, container, loading, tooltip); })
      .catch(function (e) {
        if (loading) loading.textContent = 'Failed to load: ' + e.message;
      });
  });

  function render(data, container, loading, tooltip) {
    if (loading) loading.style.display = 'none';

    if (!data.tags || data.tags.length === 0) {
      container.innerHTML = '<div class="viz-empty"><p>No tags yet — add posts with <code>tags:</code> in front matter.</p></div>';
      return;
    }

    var rect = container.getBoundingClientRect();
    var width = rect.width;
    var height = Math.max(rect.height, 400);
    var size = Math.min(width, height);

    var svg = d3.select(container)
      .append('svg')
      .attr('viewBox', [0, 0, width, height])
      .attr('role', 'img')
      .attr('aria-label', 'Tag bubble chart showing ' + data.tags.length + ' tags sized by post count');

    var g = svg.append('g')
      .attr('transform', 'translate(' + (width / 2) + ',' + (height / 2) + ')');

    var root = d3.hierarchy({ children: data.tags })
      .sum(function (d) { return d.note_count || 0; })
      .sort(function (a, b) { return b.value - a.value; });

    d3.pack().size([size * 0.9, size * 0.9]).padding(6)(root);

    var node = g.selectAll('g')
      .data(root.leaves())
      .join('g')
      .attr('transform', function (d) {
        return 'translate(' + (d.x - size * 0.45) + ',' + (d.y - size * 0.45) + ')';
      });

    node.append('circle')
      .attr('r', function (d) { return d.r; })
      .attr('fill', function (d, i) { return PALETTE[i % PALETTE.length]; })
      .attr('fill-opacity', 0.7)
      .attr('stroke', 'currentColor')
      .attr('stroke-opacity', 0.3)
      .style('cursor', 'pointer')
      .on('mouseenter', function (event, d) {
        if (!tooltip) return;
        tooltip.innerHTML = '<strong>' + escapeHtml(d.data.name) + '</strong><br>' +
                            d.data.note_count + ' post' + (d.data.note_count === 1 ? '' : 's');
        tooltip.style.display = 'block';
      })
      .on('mousemove', function (event) {
        if (!tooltip) return;
        tooltip.style.left = (event.pageX + 12) + 'px';
        tooltip.style.top = (event.pageY + 12) + 'px';
      })
      .on('mouseleave', function () {
        if (tooltip) tooltip.style.display = 'none';
      })
      .on('click', function (event, d) {
        window.location = '/tags/' + slugify(d.data.name) + '/';
      });

    node.append('text')
      .attr('dy', '0.3em')
      .attr('text-anchor', 'middle')
      .attr('pointer-events', 'none')
      .style('font-size', function (d) {
        return Math.max(8, Math.min(d.r / 2.5, 18)) + 'px';
      })
      .style('fill', 'currentColor')
      .text(function (d) {
        return d.r > 22 ? d.data.name : '';
      });
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function slugify(s) {
    return String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  }
})();
