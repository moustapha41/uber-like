interface LineChartProps {
  data: { label: string; value: number }[];
  color?: string;
}

export default function LineChart({ data, color = '#3B82F6' }: LineChartProps) {
  const maxValue = Math.max(...data.map((d) => d.value), 1);
  const minValue = Math.min(...data.map((d) => d.value), 0);
  const range = maxValue - minValue || 1;

  const points = data.map((item, index) => {
    const x = (index / (data.length - 1)) * 100;
    const y = 100 - ((item.value - minValue) / range) * 80 - 10;
    return { x, y, value: item.value };
  });

  const pathD = points.reduce((path, point, index) => {
    if (index === 0) return `M ${point.x} ${point.y}`;
    const prevPoint = points[index - 1];
    const cpX = (prevPoint.x + point.x) / 2;
    return `${path} Q ${cpX} ${prevPoint.y}, ${cpX} ${(prevPoint.y + point.y) / 2} T ${point.x} ${point.y}`;
  }, '');

  return (
    <div className="space-y-4">
      <div className="relative h-64 bg-slate-50 rounded-lg p-4">
        <svg className="w-full h-full" viewBox="0 0 100 100" preserveAspectRatio="none">
          <defs>
            <linearGradient id="gradient" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" stopColor={color} stopOpacity="0.2" />
              <stop offset="100%" stopColor={color} stopOpacity="0" />
            </linearGradient>
          </defs>

          <path
            d={`${pathD} L 100 100 L 0 100 Z`}
            fill="url(#gradient)"
          />

          <path
            d={pathD}
            fill="none"
            stroke={color}
            strokeWidth="0.5"
            vectorEffect="non-scaling-stroke"
          />

          {points.map((point, index) => (
            <circle
              key={index}
              cx={point.x}
              cy={point.y}
              r="1"
              fill={color}
              vectorEffect="non-scaling-stroke"
            />
          ))}
        </svg>

        <div className="absolute top-2 right-2 bg-white px-3 py-1 rounded-full shadow-sm">
          <span className="text-xs font-semibold text-slate-600">
            Max: {maxValue}
          </span>
        </div>
      </div>

      <div className="flex items-center justify-between text-xs text-slate-600">
        {data.map((item, index) => (
          <span key={index} className="font-medium">
            {item.label}
          </span>
        ))}
      </div>
    </div>
  );
}
